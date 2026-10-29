import 'chat_realtime_controller.dart';
import '../../workspace/presentation/workspace_home_screen.dart';
import 'dart:async';

import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../files/presentation/pending_uploads_screen.dart';
import '../../printers/presentation/printer_monitoring_screen.dart';
import '../../scanner/presentation/scanner_session_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../files/presentation/my_files_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../it_assets/presentation/mobile_it_asset_scanner_screen.dart';
import '../../profile/presentation/notification_settings_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../profile/presentation/storage_management_screen.dart';
import '../../tickets/presentation/tickets_screen.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../providers/chat_folders_provider.dart';
import 'chat_admin_management_screen.dart';
import 'chat_appearance.dart';
import 'chat_appearance_screen.dart';
import 'contacts_screen.dart';
import 'conversation_screen.dart';
import 'departments_screen.dart';
import 'favorite_messages_screen.dart';
import 'rooms_screen.dart';
import 'widgets/chat_avatar.dart';
import 'widgets/new_conversation_sheet.dart';
import 'widgets/chat_folder_inline_item.dart';
import 'widgets/create_chat_folder_dialog.dart';

class ChatHomeScreen extends ConsumerStatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  ConsumerState<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends ConsumerState<ChatHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Map<String, Map<String, String>> _typingByConversationId =
      <String, Map<String, String>>{};
  StreamSubscription<ChatSocketEvent>? _chatEventsSubscription;
  bool _isSearchExpanded = false;
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    _chatEventsSubscription = ref.read(chatSocketServiceProvider).events.listen(
      (event) {
        if (!mounted) {
          return;
        }
        final conversationId = event.payload['conversationId']?.toString();
        if (conversationId == null || conversationId.isEmpty) {
          return;
        }
        final currentUserId = ref.read(authControllerProvider).valueOrNull?.id;
        switch (event.type) {
          case 'typing':
            final typingUserId = _extractTypingUserId(event.payload);
            final typingUserName = _extractTypingUserName(event.payload);
            if (typingUserId == null ||
                typingUserName == null ||
                typingUserId == currentUserId) {
              return;
            }
            setState(() {
              final entry = _typingByConversationId.putIfAbsent(
                conversationId,
                () => <String, String>{},
              );
              entry[typingUserId] = typingUserName;
            });
            return;
          case 'stop_typing':
            final typingUserId = _extractTypingUserId(event.payload);
            if (typingUserId == null) {
              return;
            }
            setState(() {
              final entry = _typingByConversationId[conversationId];
              entry?.remove(typingUserId);
              if (entry == null || entry.isEmpty) {
                _typingByConversationId.remove(conversationId);
              }
            });
            return;
          case 'receive_message':
            if (_typingByConversationId.containsKey(conversationId)) {
              setState(() {
                _typingByConversationId.remove(conversationId);
              });
            }
            return;
        }
      },
    );
  }

  @override
  void dispose() {
    _chatEventsSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String? _extractTypingUserId(Map<String, dynamic> payload) {
    return payload['userId']?.toString() ??
        payload['senderId']?.toString() ??
        payload['memberId']?.toString();
  }

  String? _extractTypingUserName(Map<String, dynamic> payload) {
    final value =
        payload['fullName']?.toString() ??
        payload['displayName']?.toString() ??
        payload['name']?.toString();
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  String? _typingPreviewText(ChatConversation conversation) {
    final typingUsers = _typingByConversationId[conversation.id]?.values
        .toList();
    if (typingUsers == null || typingUsers.isEmpty) {
      return null;
    }
    if (conversation.type == 'direct') {
      return 'يكتب الآن...';
    }
    if (typingUsers.length == 1) {
      return '${typingUsers.first} يكتب الآن...';
    }
    if (typingUsers.length == 2) {
      return '${typingUsers[0]} و${typingUsers[1]} يكتبان الآن...';
    }
    return '${typingUsers.length} أعضاء يكتبون الآن...';
  }

  Future<void> _showCreateDialog(AppUser user) async {
    final created = await NewConversationSheet.show(
      context,
      currentUser: user,
    );

    if (created != null && mounted) {
      Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => ConversationScreen(conversation: created),
        ),
      );
    }
  }

  List<ChatConversation> _filterConversations(
    List<ChatConversation> conversations,
    String currentUserId,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = conversations.where((conversation) {
      final title = conversation.displayTitle(currentUserId).toLowerCase();
      final subtitle = conversation.lastMessage?.content.toLowerCase() ?? '';
      return query.isEmpty || title.contains(query) || subtitle.contains(query);
    }).toList();

    final active = filtered
        .where((conversation) => !conversation.isArchived)
        .toList();
    final archived = filtered
        .where((conversation) => conversation.isArchived)
        .toList();

    int byPinnedThenRecent(ChatConversation a, ChatConversation b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return _conversationActivityAt(b).compareTo(_conversationActivityAt(a));
    }

    active.sort(byPinnedThenRecent);
    archived.sort(byPinnedThenRecent);
    return [...active, ...archived];
  }

  DateTime _conversationActivityAt(ChatConversation conversation) {
    return conversation.lastMessage?.createdAt ?? conversation.updatedAt;
  }

  Future<void> _updateConversationPreferences(
    ChatConversation conversation, {
    bool? isMuted,
    bool? isArchived,
    bool? isPinned,
    bool? isFavorite,
  }) async {
    try {
      await ref
          .read(chatOverviewControllerProvider.notifier)
          .updateConversationPreferences(
            conversationId: conversation.id,
            isMuted: isMuted,
            isArchived: isArchived,
            isPinned: isPinned,
            isFavorite: isFavorite,
          );
    } catch (error) {
      final text = error.toString().toLowerCase();
      final notFound =
          text.contains('conversation not found') ||
          text.contains('404') ||
          text.contains('غير موجود');
      if (notFound && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تنفيذ العملية بالفعل')),
        );
        return;
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteConversation(ChatConversation conversation) async {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    final canDeleteForEveryone = authUser?.role == 'admin' ||
        conversation.createdBy == authUser?.id ||
        conversation.type == 'direct';

    final action = await showModalBottomSheet<String>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFB91C1C),
              ),
              title: const Text(
                'حذف المحادثة من قائمتي',
                style: TextStyle(color: Color(0xFFB91C1C)),
              ),
              subtitle: const Text(
                'إزالة المحادثة ومسح رسائلها من جهازك',
              ),
              onTap: () => Navigator.of(context).pop('self'),
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('مسح الرسائل فقط'),
              subtitle: const Text(
                'تظل المحادثة في القائمة لكن بدون الرسائل القديمة',
              ),
              onTap: () => Navigator.of(context).pop('clear'),
            ),
            if (conversation.type != 'direct')
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('مغادرة المجموعة'),
                onTap: () => Navigator.of(context).pop('leave'),
              ),
            if (canDeleteForEveryone)
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFB91C1C),
                ),
                title: Text(
                  conversation.type == 'direct'
                      ? 'حذف نهائي للطرفين'
                      : 'حذف نهائي للجميع',
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
                subtitle: const Text(
                  'سيتم حذف كل الرسائل والمحادثة نهائيًا من كل الأطراف',
                ),
                onTap: () => Navigator.of(context).pop('global'),
              ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) {
      return;
    }

    try {
      if (action == 'self') {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف المحادثة'),
            content: const Text('هل أنت متأكد من حذف هذه المحادثة من قائمتك؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                ),
                child: const Text('حذف'),
              ),
            ],
          ),
        );
        if (confirm != true || !mounted) return;
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .deleteConversation(conversation.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف المحادثة من قائمتك')),
          );
        }
        return;
      }
      if (action == 'clear') {
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .clearConversationMessages(conversation.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم مسح الرسائل بنجاح')));
        }
        return;
      }
      if (action == 'leave') {
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .leaveConversation(conversation.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تمت مغادرة المجموعة')));
        }
        return;
      }
      if (action == 'global') {
        final shouldDeleteGlobal = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              conversation.type == 'direct'
                  ? 'تأكيد الحذف النهائي للطرفين'
                  : 'تأكيد الحذف النهائي للجميع',
            ),
            content: Text(
              conversation.type == 'direct'
                  ? 'سيتم حذف المحادثة ورسائلها نهائيًا عندك وعند الطرف الآخر.'
                  : 'سيتم حذف المحادثة ورسائلها نهائيًا للجميع.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                ),
                child: const Text('حذف نهائي'),
              ),
            ],
          ),
        );
        if (shouldDeleteGlobal != true || !mounted) {
          return;
        }
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .deleteConversation(conversation.id, deleteForEveryone: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم الحذف النهائي بنجاح')),
          );
        }
      }
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
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ConversationScreen(conversation: conversation),
      ),
    );
  }

  Future<void> _openOrStartDirectConversation(
    ChatDirectoryUser user,
    ChatOverviewData overview,
    String currentUserId,
  ) async {
    ChatConversation? existingConversation;
    for (final conversation in overview.directConversations) {
      final hasPeer = conversation.members.any((entry) => entry.id == user.id);
      final hasCurrentUser = conversation.members.any(
        (entry) => entry.id == currentUserId,
      );
      if (hasPeer && hasCurrentUser) {
        existingConversation = conversation;
        break;
      }
    }

    final conversation =
        existingConversation ??
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .createDirectConversation(user.id);

    if (!mounted) {
      return;
    }
    await _openConversation(conversation);
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchController.clear();
      }
    });
    if (_isSearchExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    } else {
      _searchFocusNode.unfocus();
    }
  }

  void _handleWorkspaceAction(String value) {
    switch (value) {
      case 'chat':
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case 'workspace':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WorkspaceHomeScreen()),
        );
        break;
      case 'chatFolders':
        _showCreateFolderDialog();
        break;
      case 'files':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MyFilesScreen()));
        break;
      case 'sendDesktop':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                const MyFilesScreen(launchDesktopSendPickerOnOpen: true),
          ),
        );
        break;
      case 'home':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
        break;
      case 'itAssetsScanner':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MobileItAssetScannerScreen()),
        );
        break;
      case 'profile':
        Navigator.of(
          context,
        ).push(CupertinoPageRoute(builder: (_) => const ProfileScreen()));
        break;
      case 'notifications':
        Navigator.of(context).push(
          CupertinoPageRoute(builder: (_) => const NotificationSettingsScreen()),
        );
        break;
      case 'storage':
        Navigator.of(context).push(
          CupertinoPageRoute(builder: (_) => const StorageManagementScreen()),
        );
        break;
      case 'favoriteMessages':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FavoriteMessagesScreen()),
        );
        break;
      case 'theme':
        ref.read(themeModeControllerProvider.notifier).cycleThemeMode();
        break;
      case 'admin':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ChatAdminManagementScreen()),
        );
        break;
      case 'appearance':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ChatAppearanceScreen()));
        break;
      case 'localFiles':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PendingUploadsScreen()),
        );
        break;
      case 'scanner':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ScannerSessionScreen()),
        );
        break;
      case 'printers':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MobilePrinterMonitoringScreen()),
        );
        break;
      case 'tickets':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TicketsScreen(embedded: false),
          ),
        );
        break;
      case 'logout':
        _confirmLogout();
        break;
    }
  }

  Future<void> _showCreateFolderDialog() async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final authUser = ref.read(authControllerProvider).valueOrNull;
    await showCreateOrEditChatFolderDialog(
      context,
      availableConversations: overview?.conversations ?? const [],
      currentUserId: authUser?.id,
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تسجيل الخروج'),
            content: const Text('هل تريد تسجيل الخروج من التطبيق الآن؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldLogout || !mounted) {
      return;
    }
    await ref.read(authControllerProvider.notifier).logout();
  }

  bool _matchesConversationQuery(
    ChatConversation conversation,
    String currentUserId,
    String query,
  ) {
    if (query.isEmpty) {
      return true;
    }
    final title = conversation.displayTitle(currentUserId).toLowerCase();
    final preview = _conversationPreview(conversation).toLowerCase();
    final description = conversation.description.toLowerCase();
    return title.contains(query) ||
        preview.contains(query) ||
        description.contains(query);
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

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final overviewState = ref.watch(chatOverviewControllerProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final chatPreferences =
        authUser?.chatPreferences ?? ChatPreferences.defaults;
    final appearance = ChatAppearanceCatalog.resolveAppearance(
      preferences: chatPreferences,
      isDark: isDark,
      colorScheme: colorScheme,
    );
    final shellBackground = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: shellBackground,
      appBar: _selectedNavIndex == 2
          ? null
          : AppBar(
              title: Builder(
                builder: (context) {
                  final realtime = ref.watch(chatRealtimeControllerProvider);
                  final String? statusText = _selectedNavIndex == 0
                      ? switch (realtime.status) {
                          ChatConnectionStatus.connecting => 'جارٍ الاتصال...',
                          ChatConnectionStatus.reconnecting => 'جارٍ الاتصال...',
                          ChatConnectionStatus.disconnected => 'في انتظار الشبكة...',
                          _ => null,
                        }
                      : null;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        switch (_selectedNavIndex) {
                          0 => 'المحادثات',
                          1 => 'دليل الموظفين',
                          _ => 'الإعدادات والمزيد',
                        },
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      if (statusText != null)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: appearance.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: appearance.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              centerTitle: true,
              leading: _selectedNavIndex == 0 && authUser != null
                  ? Builder(
                      builder: (context) => Padding(
                        padding: const EdgeInsetsDirectional.only(start: 12),
                        child: GestureDetector(
                          onTap: () => Scaffold.of(context).openEndDrawer(),
                          child: Center(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ChatAvatar(
                                  radius: 17,
                                  backgroundColor: appearance.accent.withValues(
                                    alpha: isDark ? 0.22 : 0.14,
                                  ),
                                  avatarUrl: authUser.avatarUrl,
                                  fallback: Text(
                                    _avatarLabel(
                                      authUser.fullName.trim().isNotEmpty
                                          ? authUser.fullName.trim()
                                          : authUser.username,
                                    ),
                                    style: TextStyle(
                                      color: appearance.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                PositionedDirectional(
                                  end: -1,
                                  bottom: -1,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF1C1C1E)
                                            : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
              actions: [
                if (_selectedNavIndex == 0) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: _HeaderIconButton(
                      tooltip: _isSearchExpanded ? 'إغلاق البحث' : 'بحث',
                      icon: _isSearchExpanded
                          ? Icons.close_rounded
                          : Icons.search_rounded,
                      appearance: appearance,
                      isDark: isDark,
                      onPressed: _toggleSearch,
                    ),
                  ),
                  if (authUser != null) ...[
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: _HeaderIconButton(
                        tooltip: 'محادثة جديدة',
                        icon: Icons.edit_square,
                        appearance: appearance,
                        isDark: isDark,
                        onPressed: () => _showCreateDialog(authUser),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: _HeaderIconButton(
                        tooltip: 'مساحة العمل والملاحظات',
                        icon: Icons.edit_note_rounded,
                        appearance: appearance,
                        isDark: isDark,
                        onPressed: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) => const WorkspaceHomeScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
                Builder(
                  builder: (context) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _HeaderIconButton(
                      tooltip: 'القائمة',
                      icon: Icons.menu_rounded,
                      appearance: appearance,
                      isDark: isDark,
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ),
                ),
              ],
            ),
      endDrawer: _ChatWorkspaceDrawer(
        user: authUser,
        appearance: appearance,
        isDark: isDark,
        onSelected: _handleWorkspaceAction,
        showAdmin:
            authUser?.can('canCreateUsers') == true ||
            authUser?.can('canCreateDepartments') == true,
        themeMode: themeMode,
      ),
      bottomNavigationBar: _AppleBottomNavigationBar(
        currentIndex: _selectedNavIndex,
        onTap: (index) => setState(() => _selectedNavIndex = index),
        totalUnread: overviewState.valueOrNull?.totalUnread ?? 0,
        accentColor: appearance.accent,
        isDark: isDark,
      ),
      body: SafeArea(
        child: overviewState.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          skipError: true,
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
            children: const [
              ShimmerSkeleton(height: 56, borderRadius: 20),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ShimmerSkeleton(height: 36, borderRadius: 12),
                  ),
                  SizedBox(width: 8),
                  ShimmerSkeleton(width: 72, height: 36, borderRadius: 12),
                ],
              ),
              SizedBox(height: 12),
              ShimmerSkeleton(height: 98, borderRadius: 22),
              SizedBox(height: 8),
              ShimmerSkeleton(height: 98, borderRadius: 22),
            ],
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'تعذر تحميل المحادثات',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => ref
                        .read(chatOverviewControllerProvider.notifier)
                        .refresh(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
          data: (overview) {
            final folders = ref.watch(chatFoldersProvider).valueOrNull ?? [];
            final folderConversationIds = folders
                .expand((f) => f.conversationIds)
                .toSet();
            final currentUserId = authUser?.id ?? '';
            final searchQuery = _searchController.text.trim().toLowerCase();
            final totalUnread = overview.totalUnread;
            final displayName =
                (authUser?.fullName.trim().isNotEmpty ?? false)
                ? authUser!.fullName.trim()
                : (authUser?.username ?? 'المحادثات');
            final conversations = _filterConversations(
              overview.conversations,
              currentUserId,
            );
            final ungroupedConversations = conversations
                .where(
                  (conversation) =>
                      !conversation.isArchived &&
                      !folderConversationIds.contains(conversation.id),
                )
                .toList();
            final directConversations = conversations
                .where(
                  (conversation) =>
                      conversation.type == 'direct' &&
                      !conversation.isArchived,
                )
                .toList();
            final favoriteConversations = conversations
                .where((conversation) => conversation.isFavorite)
                .toList();
            final archivedConversations = conversations
                .where((conversation) => conversation.isArchived)
                .toList();
            final groupedSpaces = overview.conversations
                .where(
                  (conversation) =>
                      conversation.type != 'direct' &&
                      _matchesConversationQuery(
                        conversation,
                        currentUserId,
                        searchQuery,
                      ),
                )
                .toList();
            final departmentById = {
              for (final department in overview.departments)
                department.id: department,
            };
            final branchById = {
              for (final branch in overview.branches) branch.id: branch,
            };
            final usersByDepartment =
                <DepartmentSummary?, List<ChatDirectoryUser>>{};
            final usersByBranch = <BranchSummary?, List<ChatDirectoryUser>>{};
            for (final user in overview.users) {
              if (user.id == currentUserId) {
                continue;
              }
              final department = departmentById[user.departmentId];
              final branch = branchById[user.branchId];
              if (!_matchesUserQuery(user, department, searchQuery)) {
                final branchName = branch?.name.toLowerCase() ?? '';
                final displayName = user.displayName.toLowerCase();
                final username = user.username.toLowerCase();
                final matchesBranch =
                    searchQuery.isEmpty ||
                    displayName.contains(searchQuery) ||
                    username.contains(searchQuery) ||
                    branchName.contains(searchQuery);
                if (!matchesBranch) {
                  continue;
                }
              }
              usersByDepartment
                  .putIfAbsent(department, () => <ChatDirectoryUser>[])
                  .add(user);
              usersByBranch
                  .putIfAbsent(branch, () => <ChatDirectoryUser>[])
                  .add(user);
            }
            final orderedDepartmentEntries = [
              for (final department in overview.departments)
                if (usersByDepartment[department]?.isNotEmpty == true)
                  MapEntry(department, usersByDepartment[department]!),
              if (usersByDepartment[null]?.isNotEmpty == true)
                MapEntry<DepartmentSummary?, List<ChatDirectoryUser>>(
                  null,
                  usersByDepartment[null]!,
                ),
            ];
            final orderedBranchEntries = [
              for (final branch in overview.branches)
                if (usersByBranch[branch]?.isNotEmpty == true)
                  MapEntry(branch, usersByBranch[branch]!),
              if (usersByBranch[null]?.isNotEmpty == true)
                MapEntry<BranchSummary?, List<ChatDirectoryUser>>(
                  null,
                  usersByBranch[null]!,
                ),
            ];

            if (_selectedNavIndex == 1) {
              // ── Tab 1: Directory ──
              return DefaultTabController(
                key: const ValueKey('chat_home_directory_tab_controller'),
                length: 3,
                child: Column(
                  children: [
                    _buildPillTabBar(['الأقسام', 'الفروع', 'الأفراد'], appearance, isDark),
                    Expanded(
                      child: TabBarView(
                        children: [
                          DepartmentsScreen(
                            currentUser: authUser,
                            conversations: _filterConversations(
                              overview.departmentConversations,
                              currentUserId,
                            ),
                            departments: overview.departments,
                            users: overview.users,
                            onUserTap: (user) => _openOrStartDirectConversation(
                              user,
                              overview,
                              currentUserId,
                            ),
                          ),
                          RefreshIndicator(
                            onRefresh: () => ref
                                .read(chatOverviewControllerProvider.notifier)
                                .refresh(),
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                              children: [
                                if (orderedBranchEntries.isEmpty)
                                  _InlineEmptyState(
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
                                        (a, b) => a.displayName.compareTo(
                                          b.displayName,
                                        ),
                                      );
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _DepartmentDirectorySection(
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
                                        icon: Icons.account_tree_rounded,
                                        conversationForUser: (user) {
                                          for (final conversation
                                              in overview.directConversations) {
                                            final hasPeer = conversation.members
                                                .any(
                                                  (member) =>
                                                      member.id == user.id,
                                                );
                                            final hasCurrent = conversation
                                                .members
                                                .any(
                                                  (member) =>
                                                      member.id == currentUserId,
                                                );
                                            if (hasPeer && hasCurrent) {
                                              return conversation;
                                            }
                                          }
                                          return null;
                                        },
                                        onUserTap: (user) =>
                                            _openOrStartDirectConversation(
                                              user,
                                              overview,
                                              currentUserId,
                                            ),
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                          ContactsScreen(
                            currentUser: authUser,
                            users: overview.users,
                            departments: overview.departments,
                            onStartDirectConversation: ref
                                .read(chatOverviewControllerProvider.notifier)
                                .createDirectConversation,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            if (_selectedNavIndex == 2) {
              // ── Tab 2: Scan & Documents ──
              return const HomeScreen();
            }

            if (_selectedNavIndex == 3) {
              // ── Tab 3: More / Settings ──
              return _buildMoreSettingsView(authUser, appearance, isDark, themeMode);
            }

            // ── Tab 0: Chats ──
            return DefaultTabController(
              key: const ValueKey('chat_home_chats_tab_controller'),
              length: 5,
              child: Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: _isSearchExpanded
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFFE5E5EA).withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'ابحث في المحادثات...',
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white38
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                    color: Color(0xFF8E8E93),
                                  ),
                                  suffixIcon:
                                      _searchController.text.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'مسح البحث',
                                          icon: const Icon(
                                            Icons.cancel_rounded,
                                            size: 18,
                                            color: Color(0xFF8E8E93),
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {});
                                          },
                                        ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  isDense: true,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  _buildPillTabBar(['الكل', 'مباشر', 'المجموعات', 'المفضلة', 'المؤرشفة'], appearance, isDark),
                  Expanded(
                    child: TabBarView(
                      children: [
                        RefreshIndicator(
                          onRefresh: () async {
                            await ref
                                .read(chatOverviewControllerProvider.notifier)
                                .refresh();
                            await ref
                                .read(chatFoldersProvider.notifier)
                                .refresh();
                          },
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 6, 0, 80),
                            children: [
                              if (folders.isNotEmpty)
                                ...folders.map(
                                  (folder) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: ChatFolderInlineItem(
                                      folder: folder,
                                      currentUserId: currentUserId,
                                      conversations: folder.conversationIds
                                          .map(
                                            (id) => overview.conversations
                                                .firstWhere(
                                                  (c) => c.id == id,
                                                  orElse: () =>
                                                      ChatConversation(
                                                        id: id,
                                                        type: 'unknown',
                                                        name: '',
                                                        description: '',
                                                        departmentId: null,
                                                        createdBy: null,
                                                        members: [],
                                                        admins: [],
                                                        broadcastPublisherIds:
                                                            [],
                                                        blockedMemberIds: [],
                                                        pinnedMessage: null,
                                                        lastMessage: null,
                                                        unreadCount: 0,
                                                        isArchived: false,
                                                        isMuted: false,
                                                        isPinned: false,
                                                        isFavorite: false,
                                                        isActive: false,
                                                        createdAt:
                                                            DateTime.now(),
                                                        updatedAt:
                                                            DateTime.now(),
                                                      ),
                                                ),
                                          )
                                          .where((c) => c.type != 'unknown')
                                          .toList(),
                                      buildConversation: (c) => Padding(
                                        padding: EdgeInsets.zero,
                                        child: _ConversationCard(
                                          conversation: c,
                                          currentUserId: currentUserId,
                                          typingPreviewText: _typingPreviewText(
                                            c,
                                          ),
                                          appearance: appearance,
                                          isDark: isDark,
                                          onTap: () => _openConversation(c),
                                          onTogglePin: () =>
                                              _updateConversationPreferences(
                                                c,
                                                isPinned: !c.isPinned,
                                              ),
                                          onToggleMute: () =>
                                              _updateConversationPreferences(
                                                c,
                                                isMuted: !c.isMuted,
                                              ),
                                          onToggleFavorite: () =>
                                              _updateConversationPreferences(
                                                c,
                                                isFavorite: !c.isFavorite,
                                              ),
                                          onDeleteConversation: () =>
                                              _deleteConversation(c),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const ChatFolderDropZone(),
                              if (ungroupedConversations.isNotEmpty) ...[
                                ...ungroupedConversations
                                    .map(
                                      (conversation) => Padding(
                                        padding: EdgeInsets.zero,
                                        child: _ConversationCard(
                                          conversation: conversation,
                                          currentUserId: currentUserId,
                                          typingPreviewText: _typingPreviewText(
                                            conversation,
                                          ),
                                          appearance: appearance,
                                          isDark: isDark,
                                          onTap: () =>
                                              _openConversation(conversation),
                                          onTogglePin: () =>
                                              _updateConversationPreferences(
                                                conversation,
                                                isPinned:
                                                    !conversation.isPinned,
                                              ),
                                          onToggleMute: () =>
                                              _updateConversationPreferences(
                                                conversation,
                                                isMuted: !conversation.isMuted,
                                              ),
                                          onToggleFavorite: () =>
                                              _updateConversationPreferences(
                                                conversation,
                                                isFavorite:
                                                    !conversation.isFavorite,
                                              ),
                                          onDeleteConversation: () =>
                                              _deleteConversation(conversation),
                                        ),
                                      ),
                                    ),
                                const SizedBox(height: 14),
                              ],
                              if (ungroupedConversations.isEmpty && folders.isEmpty)
                                _InlineEmptyState(
                                  label: 'لا توجد محادثات نشطة بعد.\nيمكنك بدء محادثة جديدة عبر زر الإنشاء بالأعلى.',
                                  appearance: appearance,
                                  isDark: isDark,
                                  icon: Icons.chat_bubble_outline_rounded,
                                ),
                            ],
                          ),
                        ),
                        // ── Tab 1: Direct Chats ──
                        RefreshIndicator(
                          onRefresh: () async {
                            await ref
                                .read(chatOverviewControllerProvider.notifier)
                                .refresh();
                            await ref
                                .read(chatFoldersProvider.notifier)
                                .refresh();
                          },
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 6, 0, 80),
                            children: [
                              if (directConversations.isEmpty)
                                _InlineEmptyState(
                                  label:
                                      'لا توجد محادثات مباشرة حاليًا. يمكنك بدء محادثة جديدة من الدليل.',
                                  appearance: appearance,
                                  isDark: isDark,
                                )
                              else
                                ...directConversations.map(
                                  (conversation) => Padding(
                                    padding: EdgeInsets.zero,
                                    child: _ConversationCard(
                                      conversation: conversation,
                                      currentUserId: currentUserId,
                                      typingPreviewText: _typingPreviewText(
                                        conversation,
                                      ),
                                      appearance: appearance,
                                      isDark: isDark,
                                      onTap: () =>
                                          _openConversation(conversation),
                                      onTogglePin: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isPinned:
                                                !conversation.isPinned,
                                          ),
                                      onToggleMute: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isMuted: !conversation.isMuted,
                                          ),
                                      onToggleFavorite: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isFavorite:
                                                !conversation.isFavorite,
                                          ),
                                      onDeleteConversation: () =>
                                          _deleteConversation(conversation),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        RoomsScreen(
                          currentUser: authUser,
                          conversations: _filterConversations(
                            overview.roomConversations,
                            currentUserId,
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: () => ref
                              .read(chatOverviewControllerProvider.notifier)
                              .refresh(),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 6, 0, 80),
                            children: [
                              if (favoriteConversations.isEmpty)
                                _InlineEmptyState(
                                  label:
                                      'لا توجد محادثات مفضلة بعد. اختر نجمة من خيارات أي محادثة.',
                                  appearance: appearance,
                                  isDark: isDark,
                                )
                              else
                                ...favoriteConversations.map(
                                  (conversation) => Padding(
                                    padding: EdgeInsets.zero,
                                    child: _ConversationCard(
                                      conversation: conversation,
                                      currentUserId: currentUserId,
                                      typingPreviewText: _typingPreviewText(
                                        conversation,
                                      ),
                                      appearance: appearance,
                                      isDark: isDark,
                                      onTap: () =>
                                          _openConversation(conversation),
                                      onTogglePin: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isPinned: !conversation.isPinned,
                                          ),
                                      onToggleMute: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isMuted: !conversation.isMuted,
                                          ),
                                      onToggleFavorite: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isFavorite:
                                                !conversation.isFavorite,
                                          ),
                                      onDeleteConversation: () =>
                                          _deleteConversation(conversation),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: () => ref
                              .read(chatOverviewControllerProvider.notifier)
                              .refresh(),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 6, 0, 80),
                            children: [
                              if (archivedConversations.isEmpty)
                                _InlineEmptyState(
                                  label: 'لا توجد محادثات مؤرشفة حاليًا.',
                                  appearance: appearance,
                                  isDark: isDark,
                                )
                              else
                                ...archivedConversations.map(
                                  (conversation) => Padding(
                                    padding: EdgeInsets.zero,
                                    child: _ConversationCard(
                                      conversation: conversation,
                                      currentUserId: currentUserId,
                                      typingPreviewText: _typingPreviewText(
                                        conversation,
                                      ),
                                      appearance: appearance,
                                      isDark: isDark,
                                      onTap: () =>
                                          _openConversation(conversation),
                                      onTogglePin: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isPinned: !conversation.isPinned,
                                          ),
                                      onToggleMute: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isMuted: !conversation.isMuted,
                                          ),
                                      onToggleFavorite: () =>
                                          _updateConversationPreferences(
                                            conversation,
                                            isFavorite:
                                                !conversation.isFavorite,
                                          ),
                                      onDeleteConversation: () =>
                                          _deleteConversation(conversation),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPillTabBar(
    List<String> tabTitles,
    ChatResolvedAppearance appearance,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: TabBar(
          isScrollable: tabTitles.length > 4,
          tabAlignment: tabTitles.length > 4 ? TabAlignment.start : null,
          labelPadding: tabTitles.length > 4
              ? const EdgeInsets.symmetric(horizontal: 16)
              : null,
          indicatorAnimation: TabIndicatorAnimation.linear,
          indicatorSize: TabBarIndicatorSize.tab,
          splashFactory: NoSplash.splashFactory,
          labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
          unselectedLabelColor:
              isDark ? const Color(0xFF98989F) : const Color(0xFF64748B),
          indicator: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.07),
                blurRadius: 5,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: -0.1,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
            letterSpacing: -0.1,
          ),
          tabs: [
            for (final title in tabTitles) Tab(text: title),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreSettingsView(
    AppUser? user,
    ChatResolvedAppearance appearance,
    bool isDark,
    ThemeMode themeMode,
  ) {
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final dividerColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white54 : const Color(0xFF8E8E93);
    final displayName = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName.trim()
        : (user?.username ?? 'المستخدم');

    final canAdmin = user?.can('canCreateUsers') == true ||
        user?.can('canCreateDepartments') == true ||
        user?.role == 'admin';
    final canPrinters = user?.canViewPrinterModule == true || user?.role == 'admin';
    final canItAssets = user?.canScanItAssets == true ||
        user?.canScanItSpareParts == true ||
        user?.canScanItInventory == true ||
        user?.role == 'admin';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        // ── 1. Apple ID-Style Profile Card ──
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleWorkspaceAction('profile'),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  ChatAvatar(
                    radius: 28,
                    backgroundColor: appearance.accent.withValues(alpha: 0.15),
                    avatarUrl: user?.avatarUrl,
                    fallback: Text(
                      _avatarLabel(displayName),
                      style: TextStyle(
                        color: appearance.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user?.role == 'admin'
                              ? 'مسؤول النظام (Admin)'
                              : (user?.jobTitle.isNotEmpty == true
                                  ? user!.jobTitle
                                  : 'حساب موظف'),
                          style: TextStyle(
                            fontSize: 12,
                            color: subtitleColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (user?.username.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            '@${user!.username}',
                            style: TextStyle(
                              fontSize: 11,
                              color: subtitleColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 18,
                      color: isDark ? Colors.white38 : const Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // ── 2. Files & Productivity Group ──
        _buildSectionHeader('الملفات والإنتاجية', isDark),
        _buildAppleMenuGroup(
          cardColor: cardColor,
          dividerColor: dividerColor,
          children: [
            _AppleMenuTile(
              icon: CupertinoIcons.folder_fill,
              label: 'ملفاتي ومستنداتي السحابية',
              subtitle: 'استعراض وإدارة كافة الملفات المرفوعة',
              iconColor: const Color(0xFF007AFF),
              onTap: () => _handleWorkspaceAction('files'),
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.archivebox_fill,
              label: 'الملفات المحلية',
              subtitle: 'المستندات المحفوظة على ذاكرة الهاتف',
              iconColor: const Color(0xFFFF9500),
              onTap: () => _handleWorkspaceAction('localFiles'),
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.device_laptop,
              label: 'إرسال ملف إلى الكمبيوتر',
              subtitle: 'نقل سريع ومباشر للكمبيوتر عبر الشبكة',
              iconColor: const Color(0xFF5856D6),
              onTap: () => _handleWorkspaceAction('sendDesktop'),
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.viewfinder,
              label: 'الماسح الضوئي للمستندات',
              subtitle: 'التقاط صور وإنشاء PDF ممسوح بالكاميرا',
              iconColor: const Color(0xFF30B0C7),
              onTap: () => _handleWorkspaceAction('scanner'),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ── 3. Chat & Communication Group ──
        _buildSectionHeader('التواصل والمحادثات', isDark),
        _buildAppleMenuGroup(
          cardColor: cardColor,
          dividerColor: dividerColor,
          children: [
            _AppleMenuTile(
              icon: CupertinoIcons.star_fill,
              label: 'الرسائل المفضلة',
              subtitle: 'الرسائل المحفوظة للرجوع السريع إليها',
              iconColor: const Color(0xFFFFCC00),
              onTap: () => _handleWorkspaceAction('favoriteMessages'),
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.folder_badge_plus,
              label: 'مجلدات وتصنيفات الشات',
              subtitle: 'إنشاء مجلدات مخصصة لتنظيم المحادثات',
              iconColor: const Color(0xFF34C759),
              onTap: () => _handleWorkspaceAction('chatFolders'),
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.headphones,
              label: 'تذاكر الدعم والشكاوى',
              subtitle: 'إرسال ومتابعة بلاغات IT والمقترحات',
              iconColor: const Color(0xFFFF2D55),
              onTap: () => _handleWorkspaceAction('tickets'),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ── 4. Appearance & System Group ──
        _buildSectionHeader('المظهر والنظام', isDark),
        _buildAppleMenuGroup(
          cardColor: cardColor,
          dividerColor: dividerColor,
          children: [
            _AppleMenuTile(
              icon: isDark ? CupertinoIcons.moon_fill : CupertinoIcons.sun_max_fill,
              label: 'الوضع الداكن (Dark Mode)',
              subtitle: isDark ? 'الوضع الليلي مفعل حاليًا' : 'الوضع النهاري مفعل حاليًا',
              iconColor: const Color(0xFFFF9500),
              trailing: CupertinoSwitch(
                value: isDark,
                activeColor: const Color(0xFF007AFF),
                onChanged: (val) {
                  ref.read(themeModeControllerProvider.notifier).setThemeMode(
                    val ? ThemeMode.dark : ThemeMode.light,
                  );
                },
              ),
              onTap: () {
                ref.read(themeModeControllerProvider.notifier).setThemeMode(
                  isDark ? ThemeMode.light : ThemeMode.dark,
                );
              },
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.paintbrush_fill,
              label: 'مظهر وخلفيات المحادثات',
              subtitle: 'تخصيص ثيمات الشات وفقاعات الرسائل',
              iconColor: const Color(0xFFAF52DE),
              onTap: () => _handleWorkspaceAction('appearance'),
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.bell_fill,
              label: 'إعدادات الإشعارات والتنبيهات',
              subtitle: 'نغمات الرسائل، الاهتزاز، وإشعارات الشات',
              iconColor: const Color(0xFFFF3B30),
              onTap: () => _handleWorkspaceAction('notifications'),
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.circle_grid_hex_fill,
              label: 'بيانات التخزين والذاكرة',
              subtitle: 'تنظيف الملفات المؤقتة وإدارة الذاكرة المخبأة',
              iconColor: const Color(0xFF34C759),
              onTap: () => _handleWorkspaceAction('storage'),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ── 5. Admin & Hardware Tools (if permitted) ──
        if (canAdmin || canPrinters || canItAssets) ...[
          _buildSectionHeader('الأدوات الإدارية والشبكة', isDark),
          _buildAppleMenuGroup(
            cardColor: cardColor,
            dividerColor: dividerColor,
            children: [
              if (canAdmin)
                _AppleMenuTile(
                  icon: CupertinoIcons.shield_fill,
                  label: 'لوحة إدارة الشات والمستخدمين',
                  subtitle: 'إدارة المستخدمين والأقسام وسجلات التدقيق',
                  iconColor: const Color(0xFF34C759),
                  onTap: () => _handleWorkspaceAction('admin'),
                ),
              if (canPrinters)
                _AppleMenuTile(
                  icon: CupertinoIcons.printer_fill,
                  label: 'مراقبة أسطول الطابعات',
                  subtitle: 'فحص الطابعات والعدادات ومستويات الأحبار',
                  iconColor: const Color(0xFF007AFF),
                  onTap: () => _handleWorkspaceAction('printers'),
                ),
              if (canItAssets)
                _AppleMenuTile(
                  icon: CupertinoIcons.barcode_viewfinder,
                  label: 'ماسح أصول IT والمخزون',
                  subtitle: 'جرد العتاد وقطع الغيار بالكاميرا والباركود',
                  iconColor: const Color(0xFF00C7BE),
                  onTap: () => _handleWorkspaceAction('itAssetsScanner'),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],

        // ── 6. Account & Session ──
        _buildSectionHeader('الحساب والأمان', isDark),
        _buildAppleMenuGroup(
          cardColor: cardColor,
          dividerColor: dividerColor,
          children: [
            _AppleMenuTile(
              icon: CupertinoIcons.person_crop_circle_fill,
              label: 'إعدادات الملف الشخصي',
              subtitle: 'تعديل البيانات، الصورة الشخصية، وكلمة المرور',
              iconColor: const Color(0xFF007AFF),
              onTap: () => _handleWorkspaceAction('profile'),
            ),
            _AppleMenuTile(
              icon: CupertinoIcons.square_arrow_right,
              label: 'تسجيل الخروج',
              subtitle: 'إنهاء الجلسة والخروج من الحساب الحالي',
              iconColor: const Color(0xFFFF3B30),
              onTap: () => _handleWorkspaceAction('logout'),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── 7. App Info Footer ──
        Center(
          child: Column(
            children: [
              Text(
                'iSmart Messenger',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white38 : const Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'الإصدار 1.2.4',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white24 : const Color(0xFFA1A1A6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 12, left: 12, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white54 : const Color(0xFF6E6E73),
          letterSpacing: -0.2,
        ),
      ),
    );
  }

  Widget _buildAppleMenuGroup({
    required Color cardColor,
    required Color dividerColor,
    required List<Widget> children,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dividerColor,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(children.length, (index) {
          final isLast = index == children.length - 1;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              children[index],
              if (!isLast)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 56.0),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: dividerColor,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Apple Minimalist Navigation & Menu Components
// ─────────────────────────────────────────────────────────────────────────────

class _AppleMenuTile extends StatelessWidget {
  const _AppleMenuTile({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white54 : const Color(0xFF8E8E93);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon, color: Colors.white, size: 18),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: subtitleColor,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: isDark ? Colors.white24 : const Color(0xFFC7C7CC),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppleBottomNavigationBar extends StatelessWidget {
  const _AppleBottomNavigationBar({
    required this.currentIndex,
    required this.onTap,
    required this.totalUnread,
    required this.accentColor,
    required this.isDark,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int totalUnread;
  final Color accentColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final items = [
      _NavTabItem(
        label: 'المحادثات',
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        badgeCount: totalUnread,
      ),
      const _NavTabItem(
        label: 'الدليل',
        icon: Icons.people_alt_outlined,
        activeIcon: Icons.people_alt_rounded,
      ),
      const _NavTabItem(
        label: 'المستندات',
        icon: Icons.folder_copy_outlined,
        activeIcon: Icons.folder_copy_rounded,
      ),
      const _NavTabItem(
        label: 'الإعدادات',
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
      ),
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF141416).withValues(alpha: 0.88)
                : Colors.white.withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: EdgeInsets.only(
            bottom: bottomPadding > 0 ? bottomPadding : 8,
            top: 7,
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = currentIndex == index;
              final activeColor = accentColor;
              final inactiveColor =
                  isDark ? const Color(0xFF98989F) : const Color(0xFF64748B);

              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (!isSelected) {
                        HapticFeedback.lightImpact();
                        onTap(index);
                      }
                    },
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 18),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? activeColor.withValues(
                                          alpha: isDark ? 0.22 : 0.13,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 200),
                                  scale: isSelected ? 1.06 : 1.0,
                                  curve: Curves.easeOutBack,
                                  child: Icon(
                                    isSelected ? item.activeIcon : item.icon,
                                    size: 23,
                                    color: isSelected ? activeColor : inactiveColor,
                                  ),
                                ),
                              ),
                              if (item.badgeCount > 0)
                                PositionedDirectional(
                                  top: -3,
                                  end: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                      minHeight: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF3B30),
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF141416)
                                            : Colors.white,
                                        width: 1.8,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFF3B30).withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      item.badgeCount > 99
                                          ? '99+'
                                          : '${item.badgeCount}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        height: 1.05,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? activeColor : inactiveColor,
                              letterSpacing: -0.15,
                              height: 1.2,
                            ),
                            child: Text(item.label),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavTabItem {
  const _NavTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final int badgeCount;
}



class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF162534),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark
                  ? Colors.white60
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 56,
            height: 3,
            decoration: BoxDecoration(
              color: appearance.accent.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({
    required this.label,
    required this.appearance,
    required this.isDark,
    this.icon,
  });

  final String label;
  final ChatResolvedAppearance appearance;
  final bool isDark;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: appearance.accent.withValues(alpha: isDark ? 0.16 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? Icons.chat_bubble_outline_rounded,
                size: 26,
                color: appearance.accent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentDirectorySection extends StatelessWidget {
  const _DepartmentDirectorySection({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.appearance,
    required this.isDark,
    required this.users,
    required this.conversationForUser,
    required this.onUserTap,
    this.icon = Icons.apartment_rounded,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final ChatResolvedAppearance appearance;
  final bool isDark;
  final List<ChatDirectoryUser> users;
  final ChatConversation? Function(ChatDirectoryUser user) conversationForUser;
  final Future<void> Function(ChatDirectoryUser user) onUserTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.05 : 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: isDark ? colorScheme.surfaceContainer : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
              color: isDark
                  ? colorScheme.outlineVariant.withValues(alpha: 0.3)
                  : const Color(0xFFF1F5F9),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              initiallyExpanded: false,
              leading: CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.12),
                child: Icon(icon, color: accent),
              ),
              title: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('$subtitle • ${users.length} شخص'),
              children: [
                for (final user in users)
                  Padding(
                    padding: EdgeInsets.zero,
                    child: _DirectoryUserTile(
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
        ),
      ),
    );
  }
}

class _DirectoryUserTile extends StatelessWidget {
  const _DirectoryUserTile({
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
    final colorScheme = Theme.of(context).colorScheme;
    final hasConversation = existingConversation != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? colorScheme.surfaceContainer : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? colorScheme.outlineVariant.withValues(alpha: 0.3)
                    : const Color(0xFFF1F5F9),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.05 : 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Stack(
                  children: [
                    ChatAvatar(
                      radius: 22,
                      backgroundColor: accent.withValues(alpha: 0.14),
                      avatarUrl: user.avatarUrl,
                      fallback: Text(
                        _avatarLabel(user.displayName),
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _presenceColor(user.presenceStatus),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${user.username} • ${_presenceText(user)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: hasConversation
                        ? appearance.accent.withValues(alpha: 0.16)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    hasConversation ? 'فتح' : 'ابدأ شات',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: hasConversation ? accent : colorScheme.primary,
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

class _ConversationCard extends ConsumerStatefulWidget {
  const _ConversationCard({
    required this.conversation,
    required this.currentUserId,
    this.typingPreviewText,
    required this.appearance,
    required this.isDark,
    required this.onTap,
    required this.onTogglePin,
    required this.onToggleMute,
    required this.onToggleFavorite,
    required this.onDeleteConversation,
  });

  final ChatConversation conversation;
  final String currentUserId;
  final String? typingPreviewText;
  final ChatResolvedAppearance appearance;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDeleteConversation;

  @override
  ConsumerState<_ConversationCard> createState() => _ConversationCardState();
}

class _ConversationCardState extends ConsumerState<_ConversationCard> {
  bool _didDragMove = false;
  Offset? _dragStartPos;

  String _directPeerName(ChatDirectoryUser user) {
    if (user.fullName.trim().isNotEmpty) return user.fullName.trim();
    return user.username;
  }

  String _avatarLabel(String title) {
    if (title.isEmpty) return '?';
    return title.characters.first.toUpperCase();
  }

  ChatDirectoryUser? _directPeer() {
    return widget.conversation.members
        .where((m) => m.id != widget.currentUserId)
        .firstOrNull;
  }

  Color _presenceColor(String status) {
    switch (status) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'dnd':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _conversationPreview(ChatConversation conversation) {
    final last = conversation.lastMessage;
    if (last == null) return 'ابدأ المحادثة الآن';
    final body = last.content.isNotEmpty
        ? last.content
        : switch (last.messageType) {
            'poll' => '📊 استطلاع رأي',
            'checklist' => '✅ قائمة مهام',
            'image' => '📷 صورة',
            'pdf' => '📄 ملف PDF',
            'audio' => '🎙 ملاحظة صوتية',
            'file' => '📎 ملف مرفق',
            'gif' => '🎞 GIF',
            'system' => 'رسالة النظام',
            _ => 'رسالة',
          };
    final isMe = last.senderId != null && last.senderId == widget.currentUserId;
    if (conversation.type == 'direct' ||
        last.senderName.trim().isEmpty ||
        isMe) {
      return body;
    }
    return '${last.senderName}: $body';
  }

  Widget? _buildStatusIcon() {
    if (widget.typingPreviewText != null) return null;
    final last = widget.conversation.lastMessage;
    if (last == null) return null;

    final myId = widget.currentUserId.trim();
    final senderId = (last.senderId ?? '').trim();
    if (myId.isEmpty || senderId.isEmpty || senderId != myId) {
      return null;
    }

    // 1. Pending (in outbox or waiting for network) -> Clock icon
    if (last.status == 'pending' ||
        (last.id != null && last.id!.startsWith('temp_'))) {
      return const Icon(
        Icons.access_time_rounded,
        size: 13.5,
        color: Color(0xFF94A3B8), // Pending Clock
      );
    }

    // 2. Failed -> Error icon
    if (last.status == 'failed') {
      return const Icon(
        Icons.error_outline_rounded,
        size: 14.5,
        color: Color(0xFFEF4444), // Failed
      );
    }

    // 3. Seen / Read -> WhatsApp Green Double Check
    if (last.isSeenByAny(myId)) {
      return const Icon(
        Icons.done_all_rounded,
        size: 15.5,
        color: Color(0xFF16A34A), // WhatsApp Green / Read
      );
    }

    // 4. Delivered -> WhatsApp Grey Double Check
    if (last.isDeliveredToAny(myId)) {
      return const Icon(
        Icons.done_all_rounded,
        size: 15.5,
        color: Color(0xFF94A3B8), // WhatsApp Grey Double Check / Delivered
      );
    }

    // 5. Sent -> Single Grey Check
    return const Icon(
      Icons.done_rounded,
      size: 15.5,
      color: Color(0xFF94A3B8), // Single Grey Check / Sent
    );
  }

  Color _conversationAccent(String type) {
    switch (type) {
      case 'direct':
        return const Color(0xFF3B82F6);
      case 'group':
        return const Color(0xFF10B981);
      case 'department':
        return const Color(0xFF8B5CF6);
      case 'branch':
        return const Color(0xFFF59E0B);
      case 'broadcast':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF6B7280);
    }
  }

  void _showActionMenu(BuildContext context) {
    final folders = ref.read(chatFoldersProvider).value ?? [];
    final inFolders = folders
        .where((f) => f.conversationIds.contains(widget.conversation.id))
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                widget.conversation.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
              ),
              title: Text(
                widget.conversation.isPinned ? 'إلغاء التثبيت' : 'تثبيت المحادثة',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onTogglePin();
              },
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 56,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.3),
            ),
            ListTile(
              leading: Icon(
                widget.conversation.isMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_outlined,
              ),
              title: Text(
                widget.conversation.isMuted ? 'إلغاء كتم الصوت' : 'كتم المحادثة',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onToggleMute();
              },
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 56,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.3),
            ),
            ListTile(
              leading: Icon(
                widget.conversation.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: widget.conversation.isFavorite
                    ? const Color(0xFFFFB020)
                    : null,
              ),
              title: Text(
                widget.conversation.isFavorite
                    ? 'إزالة من المفضلة'
                    : 'إضافة إلى المفضلة',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onToggleFavorite();
              },
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 56,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.3),
            ),
            ListTile(
              leading: const Icon(
                Icons.folder_outlined,
                color: Color(0xFF007AFF),
              ),
              title: Text(
                inFolders.isNotEmpty ? 'إدارة المجلدات' : 'نقل إلى مجلد...',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: inFolders.isNotEmpty
                  ? Text(
                      'في: ${inFolders.map((f) => f.name).join('، ')}',
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                _showMoveToFolderSheet(context);
              },
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 56,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.3),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text(
                'مسح/مغادرة',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.onDeleteConversation();
              },
            ),
          ],
        ),
      ),
    ),
  );
  }

  void _showMoveToFolderSheet(BuildContext context) {
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
                        'اختر مجلداً للمحادثة',
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
                        'لا توجد مجلدات حالياً.\nيمكنك إنشاء مجلد جديد من القائمة أو زر (+).',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...folders.map((folder) {
                    final isMember =
                        folder.conversationIds.contains(widget.conversation.id);
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
                              conversationId: widget.conversation.id,
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
    final peer = widget.conversation.type == 'direct' ? _directPeer() : null;
    final title = widget.conversation.displayTitle(widget.currentUserId);
    final String tooltipMessage = (peer?.jobTitle.trim().isNotEmpty == true)
        ? '$title\n💼 ${peer!.jobTitle.trim()}'
        : (peer != null && peer.branchCode.isNotEmpty
            ? '$title • فرع ${peer.branchCode}'
            : title);
    final preview =
        widget.typingPreviewText ?? _conversationPreview(widget.conversation);
    final accent = _conversationAccent(widget.conversation.type);
    final colorScheme = Theme.of(context).colorScheme;
    final isTypingPreview = widget.typingPreviewText != null;
    final hasUnread = widget.conversation.unreadCount > 0;

    return LongPressDraggable<ChatConversation>(
      data: widget.conversation,
      delay: const Duration(milliseconds: 240),
      onDragStarted: () {
        HapticFeedback.mediumImpact();
        setState(() {
          _didDragMove = false;
          _dragStartPos = null;
        });
      },
      onDragUpdate: (details) {
        _dragStartPos ??= details.globalPosition;
        if ((details.globalPosition - _dragStartPos!).distance > 12) {
          _didDragMove = true;
        }
      },
      onDragCompleted: () {
        HapticFeedback.lightImpact();
      },
      onDraggableCanceled: (velocity, offset) {
        if (!_didDragMove && mounted) {
          _showActionMenu(context);
        }
      },
      feedback: Material(
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              ChatAvatar(
                radius: 22,
                backgroundColor: accent.withValues(alpha: 0.14),
                avatarUrl: (widget.conversation.type == 'direct' ? peer?.avatarUrl : widget.conversation.avatarUrl) ?? widget.conversation.avatarUrl ?? peer?.avatarUrl,
                fallback: Text(
                  peer != null
                      ? _avatarLabel(peer.displayName)
                      : _avatarLabel(title),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      preview,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.drive_file_move_rounded, color: accent, size: 22),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _buildItem(
          context,
          peer,
          title,
          preview,
          accent,
          colorScheme,
          isTypingPreview,
          hasUnread,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          splashColor: widget.appearance.accent.withValues(alpha: 0.08),
          highlightColor: widget.appearance.accent.withValues(alpha: 0.04),
          child: _buildItem(
            context,
            peer,
            title,
            preview,
            accent,
            colorScheme,
            isTypingPreview,
            hasUnread,
          ),
        ),
      ),
    );
  }

    Widget _buildItem(
    BuildContext context,
    ChatDirectoryUser? peer,
    String title,
    String preview,
    Color accent,
    ColorScheme colorScheme,
    bool isTypingPreview,
    bool hasUnread,
  ) {
    final statusIcon = _buildStatusIcon();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ChatAvatar(
                    radius: 26,
                    backgroundColor: accent.withValues(alpha: 0.14),
                    avatarUrl: (widget.conversation.type == 'direct' ? peer?.avatarUrl : widget.conversation.avatarUrl) ?? widget.conversation.avatarUrl ?? peer?.avatarUrl,
                    fallback: Text(
                      peer != null
                          ? _avatarLabel(peer.displayName)
                          : _avatarLabel(title),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  if (peer != null)
                    PositionedDirectional(
                      end: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _presenceColor(peer.presenceStatus),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.5,
                                  color: colorScheme.onSurface,
                                ),
                          ),
                        ),
                        if (widget.conversation.isPinned) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.push_pin_rounded,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                        if (widget.conversation.isFavorite) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Color(0xFFFFB020),
                          ),
                        ],
                        if (widget.conversation.isMuted) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.volume_off_rounded,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          widget.conversation.lastMessage?.createdAt != null
                              ? formatEgyptTime(
                                  widget.conversation.lastMessage!.createdAt!,
                                )
                              : DateFormat(
                                  'dd/MM',
                                ).format(widget.conversation.updatedAt.toLocal()),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: hasUnread
                                ? widget.appearance.accent
                                : colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (statusIcon != null) ...[
                          statusIcon,
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isTypingPreview
                                  ? widget.appearance.accent
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: hasUnread || isTypingPreview
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 13.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            decoration: BoxDecoration(
                              color: widget.appearance.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "${widget.conversation.unreadCount}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 78.0),
          child: Divider(
            height: 0.5,
            thickness: 0.5,
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.appearance,
    required this.isDark,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final ChatResolvedAppearance appearance;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: appearance.accent,
        backgroundColor: appearance.accent.withValues(
          alpha: isDark ? 0.16 : 0.10,
        ),
      ),
    );
  }
}

class _HeaderMoreButton extends StatelessWidget {
  const _HeaderMoreButton({
    required this.appearance,
    required this.isDark,
    required this.onSelected,
    required this.showAdmin,
    required this.themeMode,
  });

  final ChatResolvedAppearance appearance;
  final bool isDark;
  final ValueChanged<String> onSelected;
  final bool showAdmin;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'المزيد',
      onSelected: onSelected,
      color: isDark
          ? Theme.of(context).colorScheme.surfaceContainer
          : Colors.white,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'appearance',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.format_paint_outlined),
            title: Text('مظهر المحادثات'),
          ),
        ),
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(switch (themeMode) {
              ThemeMode.dark => Icons.dark_mode_outlined,
              ThemeMode.system => Icons.light_mode_outlined,
              ThemeMode.light => Icons.light_mode_outlined,
            }),
            title: const Text('تبديل الثيم'),
          ),
        ),
        if (showAdmin)
          const PopupMenuItem(
            value: 'admin',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('إدارة الشات'),
            ),
          ),
        const PopupMenuItem(
          value: 'favoriteMessages',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.star_outline_rounded),
            title: Text('الرسائل المفضلة'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: Color(0xFFB91C1C)),
            title: Text(
              'تسجيل الخروج',
              style: TextStyle(color: Color(0xFFB91C1C)),
            ),
          ),
        ),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: appearance.accent.withValues(alpha: isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.more_horiz_rounded, color: appearance.accent),
      ),
    );
  }
}

class _ChatWorkspaceDrawer extends StatelessWidget {
  const _ChatWorkspaceDrawer({
    required this.user,
    required this.appearance,
    required this.isDark,
    required this.onSelected,
    required this.showAdmin,
    required this.themeMode,
  });

  final AppUser? user;
  final ChatResolvedAppearance appearance;
  final bool isDark;
  final ValueChanged<String> onSelected;
  final bool showAdmin;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    final displayName = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName.trim()
        : (user?.username ?? 'المحادثات');

    // Apple Style Colors
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark
        ? const Color(0xFFEBEBF5).withOpacity(0.6)
        : const Color(0xFF8E8E93);
    final dividerColor = isDark
        ? const Color(0xFF38383A)
        : const Color(0xFFC6C6C8);
    final primaryColor = const Color(0xFF007AFF);

    return Drawer(
      backgroundColor: bgColor,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            // User Profile Section (iOS Style Card)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  ChatAvatar(
                    radius: 28,
                    backgroundColor: appearance.accent.withOpacity(
                      isDark ? 0.2 : 0.1,
                    ),
                    avatarUrl: user?.avatarUrl,
                    fallback: Text(
                      _avatarLabel(displayName),
                      style: TextStyle(
                        color: appearance.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'مساحة العمل',
                          style: TextStyle(
                            fontSize: 14,
                            color: subtitleColor,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Core Features Group
                  _buildMenuGroup(
                    cardColor: cardColor,
                    dividerColor: dividerColor,
                    items: [
                      _MenuItem(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'المحادثات',
                        onTap: () => onSelected('chat'),
                        iconColor: const Color(0xFF34C759), // Green
                      ),
                      _MenuItem(
                        icon: Icons.folder_open_rounded,
                        label: 'الملفات',
                        onTap: () => onSelected('files'),
                        iconColor: const Color(0xFF007AFF), // Blue
                      ),
                      _MenuItem(
                        icon: Icons.document_scanner_outlined,
                        label: 'اسكان الملفات',
                        onTap: () => onSelected('home'),
                        iconColor: const Color(0xFF5856D6), // Purple
                      ),
                      _MenuItem(
                        icon: Icons.desktop_mac_rounded,
                        label: 'إرسال للكمبيوتر',
                        onTap: () => onSelected('sendDesktop'),
                        iconColor: const Color(0xFFFF9500), // Orange
                      ),
                      if (user?.canScanItAssets == true ||
                          user?.canScanItSpareParts == true ||
                          user?.canScanItInventory == true)
                        _MenuItem(
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'ماسح أصول IT',
                          onTap: () => onSelected('itAssetsScanner'),
                          iconColor: const Color(0xFF00C7BE), // Teal
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Personal Group
                  _buildMenuGroup(
                    cardColor: cardColor,
                    dividerColor: dividerColor,
                    items: [
                      _MenuItem(
                        icon: Icons.person_outline_rounded,
                        label: 'الملف الشخصي',
                        onTap: () => onSelected('profile'),
                        iconColor: const Color(0xFF8E8E93), // Gray
                      ),
                      _MenuItem(
                        icon: Icons.star_outline_rounded,
                        label: 'الرسائل المفضلة',
                        onTap: () => onSelected('favoriteMessages'),
                        iconColor: const Color(0xFFFFCC00), // Yellow
                      ),
                      _MenuItem(
                        icon: Icons.edit_note_rounded,
                        label: 'مساحة العمل والملاحظات',
                        onTap: () => onSelected('workspace'),
                        iconColor: const Color(0xFF5856D6),
                      ),
                      _MenuItem(
                        icon: Icons.create_new_folder_outlined,
                        label: 'مجلدات المحادثات',
                        onTap: () => onSelected('chatFolders'),
                        iconColor: const Color(0xFF007AFF), // Blue
                      ),
                      _MenuItem(
                        icon: Icons.support_agent_rounded,
                        label: 'التذاكر',
                        onTap: () => onSelected('tickets'),
                        iconColor: const Color(0xFFFF2D55), // Pink
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Settings Group
                  _buildMenuGroup(
                    cardColor: cardColor,
                    dividerColor: dividerColor,
                    items: [
                      _MenuItem(
                        icon: Icons.color_lens_outlined,
                        label: 'مظهر المحادثات',
                        onTap: () => onSelected('appearance'),
                        iconColor: const Color(0xFFAF52DE), // Purple
                      ),
                      _MenuItem(
                        icon: switch (themeMode) {
                          ThemeMode.dark => Icons.dark_mode_outlined,
                          ThemeMode.system => Icons.light_mode_outlined,
                          ThemeMode.light => Icons.light_mode_outlined,
                        },
                        label: 'تبديل الثيم',
                        onTap: () => onSelected('theme'),
                        iconColor: const Color(0xFF34C759),
                      ),
                      if (showAdmin)
                        _MenuItem(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'إدارة الشات',
                          onTap: () => onSelected('admin'),
                          iconColor: const Color(0xFFFF3B30), // Red
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Logout Button (iOS destructive style)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelected('logout');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'تسجيل الخروج',
                        style: TextStyle(
                          color: Color(0xFFFF3B30),
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuGroup({
    required Color cardColor,
    required Color dividerColor,
    required List<_MenuItem> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isLast = index == items.length - 1;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DrawerTile(
                icon: item.icon,
                label: item.label,
                onTap: item.onTap,
                iconColor: item.iconColor,
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.only(
                    right: 56.0,
                  ), // Align with text
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: dividerColor,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.iconColor,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      borderRadius: BorderRadius.circular(
        16,
      ), // Match container if it's the only one, or it will clip
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Icon(
              Icons
                  .chevron_right_rounded, // Assuming Arabic RTL layout, the arrow might flip, but usually a chevron is fine
              color: isDark ? const Color(0xFF5C5C5E) : const Color(0xFFC6C6C8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

String _presenceText(ChatDirectoryUser user) {
  if (user.presenceStatus == 'online') {
    return 'متصل الآن';
  }
  if (user.presenceStatus == 'idle') {
    final at = user.lastActiveAt ?? user.lastSeen;
    if (at == null) {
      return 'خامل';
    }
    return 'خامل منذ ${formatEgyptTime(at)}';
  }
  final lastSeen = user.lastSeen ?? user.lastActiveAt;
  if (lastSeen == null) {
    return 'غير متصل';
  }
  return 'آخر ظهور ${formatEgyptDateTime(lastSeen, datePattern: 'dd/MM', separator: ' ')}';
}

Color _presenceColor(String status) => switch (status) {
  'online' => const Color(0xFF22C55E),
  'idle' => const Color(0xFFF59E0B),
  _ => const Color(0xFF94A3B8),
};

Color _conversationAccent(String type) => switch (type) {
  'department' => const Color(0xFF19A974),
  'broadcast' => const Color(0xFFE67E22),
  'group' => const Color(0xFF4A90E2),
  _ => const Color(0xFF3390EC),
};

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

String _conversationTypeLabel(String type) => switch (type) {
  'department' => 'قسم',
  'broadcast' => 'إعلان',
  'group' => 'مجموعة',
  _ => 'مباشر',
};

String _conversationPreview(ChatConversation conversation) {
  final lastMessage = conversation.lastMessage;
  if (lastMessage == null) {
    return 'ابدأ المحادثة الآن';
  }

  final body = lastMessage.content.isNotEmpty
      ? lastMessage.content
      : switch (lastMessage.messageType) {
          'poll' => '📊 استطلاع رأي',
          'checklist' => '✅ قائمة مهام',
          'image' => '📷 صورة',
          'pdf' => '📄 ملف PDF',
          'audio' => '🎙 ملاحظة صوتية',
          'file' => '📎 ملف مرفق',
          'gif' => '🎞 GIF',
          'system' => 'رسالة النظام',
          _ => 'رسالة',
        };

  if (conversation.type == 'direct' || lastMessage.senderName.trim().isEmpty) {
    return body;
  }

  return '${lastMessage.senderName}: $body';
}

String _avatarLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '؟';
  }
  return trimmed.substring(0, 1).toUpperCase();
}
