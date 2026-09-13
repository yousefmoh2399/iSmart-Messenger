import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../files/presentation/my_files_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../it_assets/presentation/mobile_it_asset_scanner_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../tickets/presentation/tickets_screen.dart';
import '../../updates/presentation/update_center_screen.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import 'chat_admin_management_screen.dart';
import 'chat_appearance.dart';
import 'chat_appearance_screen.dart';

import 'contacts_screen.dart';
import 'conversation_screen.dart';
import 'departments_screen.dart';
import 'favorite_messages_screen.dart';
import 'rooms_screen.dart';
import 'widgets/chat_avatar.dart';
import 'widgets/chat_folder_inline_item.dart';
import '../providers/chat_folders_provider.dart';

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
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    if (overview == null) {
      return;
    }

    final nameController = TextEditingController();
    final searchController = TextEditingController();
    final selectedMembers = <String>{};
    final selectedAdmins = <String>{};
    var availableUsers = <ChatDirectoryUser>[];
    var usersPage = 0;
    var hasMoreUsers = true;
    var isLoadingUsers = false;
    var userSearch = '';
    String? filterDepartmentId = user.departmentId;
    final canCreateRooms = user.role == 'admin' || user.can('canCreateRooms');
    final canSendBroadcast =
        user.role == 'admin' || user.can('canSendBroadcast');
    final types = <String>[
      'group',
      if (canCreateRooms) 'department',
      if (canSendBroadcast) 'broadcast',
    ];
    var type = types.first;
    String? departmentId = user.departmentId;

    Future<void> loadUsers(
      StateSetter setLocalState, {
      bool reset = false,
    }) async {
      if (isLoadingUsers || (!hasMoreUsers && !reset)) return;
      setLocalState(() {
        isLoadingUsers = true;
        if (reset) {
          usersPage = 0;
          hasMoreUsers = true;
          availableUsers = [];
        }
      });
      try {
        final page = await ref
            .read(chatRepositoryProvider)
            .fetchUsersPage(
              search: userSearch,
              departmentId: filterDepartmentId,
              page: usersPage + 1,
              limit: 30,
            );
        setLocalState(() {
          usersPage = page.page;
          hasMoreUsers = page.hasMore;
          final byId = <String, ChatDirectoryUser>{
            for (final entry in availableUsers) entry.id: entry,
            for (final entry in page.users)
              if (entry.id != user.id) entry.id: entry,
          };
          availableUsers = byId.values.toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
        });
      } finally {
        setLocalState(() => isLoadingUsers = false);
      }
    }

    final created = await showModalBottomSheet<ChatConversation>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          if (usersPage == 0 && !isLoadingUsers) {
            Future<void>.microtask(() => loadUsers(setLocalState, reset: true));
          }
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.86,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'محادثة جديدة',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: type,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'النوع',
                            ),
                            items: types
                                .map(
                                  (entry) => DropdownMenuItem<String>(
                                    value: entry,
                                    child: Text(switch (entry) {
                                      'department' => 'غرفة قسم',
                                      'broadcast' => 'إعلان عام',
                                      _ => 'مجموعة',
                                    }),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setLocalState(() {
                                type = value ?? type;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'الاسم',
                            ),
                          ),
                          if (type == 'department') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: departmentId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'القسم',
                              ),
                              items: overview.departments
                                  .map(
                                    (department) => DropdownMenuItem<String>(
                                      value: department.id,
                                      child: Text(department.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setLocalState(() {
                                  departmentId = value;
                                });
                              },
                            ),
                          ],
                          if (type == 'group' || type == 'broadcast') ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String?>(
                              initialValue: filterDepartmentId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'فلترة حسب القسم',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('كل الأقسام'),
                                ),
                                ...overview.departments.map(
                                  (department) => DropdownMenuItem<String?>(
                                    value: department.id,
                                    child: Text(department.name),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                filterDepartmentId = value;
                                loadUsers(setLocalState, reset: true);
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: searchController,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search_rounded),
                                labelText: 'بحث بالاسم أو اسم المستخدم',
                              ),
                              onChanged: (value) {
                                userSearch = value.trim();
                                loadUsers(setLocalState, reset: true);
                              },
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 320,
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  if (notification.metrics.extentAfter < 240) {
                                    loadUsers(setLocalState);
                                  }
                                  return false;
                                },
                                child: availableUsers.isEmpty && !isLoadingUsers
                                    ? const Center(
                                        child: Text('لا يوجد مستخدمون مطابقون'),
                                      )
                                    : ListView.builder(
                                        itemCount:
                                            availableUsers.length +
                                            (isLoadingUsers ? 1 : 0),
                                        itemBuilder: (context, index) {
                                          if (index >= availableUsers.length) {
                                            return const Padding(
                                              padding: EdgeInsets.all(16),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            );
                                          }
                                          final entry = availableUsers[index];
                                          return CheckboxListTile(
                                            value: selectedMembers.contains(
                                              entry.id,
                                            ),
                                            contentPadding: EdgeInsets.zero,
                                            title: Text(entry.displayName),
                                            subtitle: Text(entry.username),
                                            onChanged: (value) {
                                              setLocalState(() {
                                                if (value == true) {
                                                  selectedMembers.add(entry.id);
                                                } else {
                                                  selectedMembers.remove(
                                                    entry.id,
                                                  );
                                                  selectedAdmins.remove(
                                                    entry.id,
                                                  );
                                                }
                                              });
                                            },
                                          );
                                        },
                                      ),
                              ),
                            ),
                            if (type == 'broadcast') ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'المشرفون داخل البث',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...availableUsers
                                  .where(
                                    (entry) =>
                                        selectedMembers.contains(entry.id),
                                  )
                                  .map(
                                    (entry) => CheckboxListTile(
                                      value: selectedAdmins.contains(entry.id),
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(entry.displayName),
                                      subtitle: Text(entry.username),
                                      onChanged: (value) {
                                        setLocalState(() {
                                          if (value == true) {
                                            selectedAdmins.add(entry.id);
                                          } else {
                                            selectedAdmins.remove(entry.id);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                            ],
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () async {
                                final conversation = await ref
                                    .read(
                                      chatOverviewControllerProvider.notifier,
                                    )
                                    .createConversation(
                                      type: type,
                                      name: nameController.text.trim(),
                                      memberIds: selectedMembers.toList(),
                                      adminIds: selectedAdmins.toList(),
                                      departmentId: departmentId,
                                    );
                                if (context.mounted) {
                                  Navigator.pop(context, conversation);
                                }
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('إنشاء'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    // Do not dispose these immediately after the sheet completes; Android can
    // still deliver a final TextField rebuild while the route is closing.

    if (created != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
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
    final canDeleteForEveryone =
        authUser?.role == 'admin' || conversation.createdBy == authUser?.id;

    final action = await showModalBottomSheet<String>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('مسح المحادثة عندي'),
              subtitle: const Text(
                'تظل المحادثة موجودة لكن بدون الرسائل القديمة',
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
                title: const Text(
                  'حذف نهائي للجميع',
                  style: TextStyle(color: Color(0xFFB91C1C)),
                ),
                subtitle: const Text(
                  'سيتم حذف كل الرسائل نهائيًا من كل الأطراف',
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
      if (action == 'clear') {
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .deleteConversation(conversation.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم مسح المحادثة عندك')));
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
            title: const Text('تأكيد الحذف النهائي'),
            content: const Text('سيتم حذف المحادثة نهائيًا للجميع.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('حذف نهائي'),
              ),
            ],
          ),
        );
        if (shouldDeleteGlobal != true) {
          return;
        }
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .deleteConversation(conversation.id, deleteForEveryone: true);
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
      MaterialPageRoute(
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
        ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
        break;
      case 'updates':
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const UpdateCenterScreen()));
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
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'iSmart Messenger',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: Padding(
            padding: const EdgeInsets.all(8.0),
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
          centerTitle: true,

          // leading: _HeaderIconButton(
          //   tooltip: 'تحديث',
          //   icon: Icons.refresh_rounded,
          //   appearance: appearance,
          //   isDark: isDark,
          //   onPressed: () =>
          //       ref.read(chatOverviewControllerProvider.notifier).refresh(),
          // ),
          actions: [
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
        backgroundColor: shellBackground,
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
        floatingActionButton: authUser == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showCreateDialog(authUser),
                backgroundColor: appearance.accent,
                foregroundColor: appearance.outgoingTextColor,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('محادثة جديدة'),
              ),
        body: SafeArea(
          child: overviewState.when(
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
                SizedBox(height: 8),
                ShimmerSkeleton(height: 98, borderRadius: 22),
                SizedBox(height: 10),
                SizedBox(
                  width: 160,
                  child: ShimmerSkeleton(height: 14, borderRadius: 8),
                ),
                SizedBox(height: 12),
                ShimmerSkeleton(height: 126, borderRadius: 24),
                SizedBox(height: 10),
                ShimmerSkeleton(height: 126, borderRadius: 24),
              ],
            ),
            error: (error, _) => Center(child: Text(error.toString())),
            data: (overview) {
              final folders = ref.watch(chatFoldersProvider).valueOrNull ?? [];
              final folderConversationIds = folders.expand((f) => f.conversationIds).toSet();
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

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: appearance.accent.withValues(alpha: 0.4),
                                width: 2,
                              ),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: ChatAvatar(
                              radius: 20,
                              backgroundColor: appearance.accent.withValues(
                                alpha: isDark ? 0.18 : 0.14,
                              ),
                              avatarUrl: authUser?.avatarUrl,
                              fallback: Text(
                                _avatarLabel(displayName),
                                style: TextStyle(
                                  color: appearance.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
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
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF0F172A),
                                            fontSize: 16,
                                          ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF22C55E),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  totalUnread > 0
                                      ? '${overview.conversations.length} محادثة • $totalUnread غير مقروءة'
                                      : '${overview.conversations.length} محادثة',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white60
                                            : const Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          _HeaderMoreButton(
                            appearance: appearance,
                            isDark: isDark,
                            onSelected: _handleWorkspaceAction,
                            showAdmin:
                                authUser?.can('canCreateUsers') == true ||
                                authUser?.can('canCreateDepartments') == true,
                            themeMode: themeMode,
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _isSearchExpanded
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1C1C1E)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'ابحث في المحادثات والأشخاص',
                                  hintStyle: TextStyle(
                                    color: isDark
                                        ? Colors.white54
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: appearance.accent,
                                  ),
                                  suffixIcon:
                                      _searchController.text.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'مسح البحث',
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {});
                                          },
                                          icon: Icon(
                                            Icons.close_rounded,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorAnimation: TabIndicatorAnimation.elastic,
                      indicatorSize: TabBarIndicatorSize.tab,
                      splashFactory: NoSplash.splashFactory,
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark
                          ? Colors.white70
                          : const Color(0xFF64748B),
                      indicator: BoxDecoration(
                        color: appearance.accent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      dividerColor: Colors.transparent,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                      tabs: const [
                        Tab(text: 'المحادثات'),
                        Tab(text: 'المفضلة'),
                        Tab(text: 'المجموعات'),
                        Tab(text: 'المؤرشفة'),
                        Tab(text: 'التذاكر'),
                        Tab(text: 'الأقسام'),
                        Tab(text: 'الفروع'),
                        Tab(text: 'الأفراد'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: [
                        RefreshIndicator(
                          onRefresh: () => ref
                              .read(chatOverviewControllerProvider.notifier)
                              .refresh(),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
                            children: [
                              if (folders.isNotEmpty) ...folders.map((folder) => Padding(padding: const EdgeInsets.only(bottom: 2), child: ChatFolderInlineItem(folder: folder, currentUserId: currentUserId, conversations: folder.conversationIds.map((id) => overview.directConversations.firstWhere((c) => c.id == id, orElse: () => ChatConversation(id: id, type: 'unknown', name: '', description: '', departmentId: null, createdBy: null, members: [], admins: [], broadcastPublisherIds: [], blockedMemberIds: [], pinnedMessage: null, lastMessage: null, unreadCount: 0, isArchived: false, isMuted: false, isPinned: false, isFavorite: false, isActive: false, createdAt: DateTime.now(), updatedAt: DateTime.now()))).where((c) => c.type != 'unknown').toList(), buildConversation: (c) => Padding(padding: EdgeInsets.zero, child: _ConversationCard(conversation: c, currentUserId: currentUserId, typingPreviewText: _typingPreviewText(c), appearance: appearance, isDark: isDark, onTap: () => _openConversation(c), onTogglePin: () => _updateConversationPreferences(c, isPinned: !c.isPinned), onToggleMute: () => _updateConversationPreferences(c, isMuted: !c.isMuted), onToggleFavorite: () => _updateConversationPreferences(c, isFavorite: !c.isFavorite), onDeleteConversation: () => _deleteConversation(c)))))),
                              if (conversations.isNotEmpty) ...[
                                _HomeSectionHeader(
                                  title: 'أحدث المحادثات',
                                  subtitle:
                                      'آخر المحادثات المباشرة والنشطة الخاصة بك.',
                                  appearance: appearance,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 8),
                                ...conversations
                                    .take(6)
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
                              _HomeSectionHeader(
                                title: 'مجموعاتي',
                                subtitle: groupedSpaces.isEmpty
                                    ? 'لا توجد مجموعات أو غرف مطابقة حاليًا.'
                                    : '${groupedSpaces.length} مجموعة وغرفة وإعلان تظهر لك مباشرة.',
                                appearance: appearance,
                                isDark: isDark,
                              ),
                              const SizedBox(height: 8),
                              if (groupedSpaces.isEmpty)
                                _InlineEmptyState(
                                  label:
                                      'لا توجد مجموعات أو غرف ضمن نتائج البحث الحالية.',
                                  appearance: appearance,
                                  isDark: isDark,
                                )
                              else
                                ...groupedSpaces.map(
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
                              const SizedBox(height: 16),
                              _HomeSectionHeader(
                                title: 'الدليل حسب الأقسام',
                                subtitle:
                                    'كل الموظفين ظاهرون حتى لو لم تبدأ محادثة معهم بعد.',
                                appearance: appearance,
                                isDark: isDark,
                              ),
                              const SizedBox(height: 8),
                              if (orderedDepartmentEntries.isEmpty)
                                _InlineEmptyState(
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
                                      (a, b) => a.displayName.compareTo(
                                        b.displayName,
                                      ),
                                    );
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _DepartmentDirectorySection(
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
                              if (conversations.isEmpty &&
                                  groupedSpaces.isEmpty &&
                                  orderedDepartmentEntries.isEmpty)
                                Padding(
                                  padding: EdgeInsets.only(top: 14),
                                  child: _InlineEmptyState(
                                    label:
                                        'لا توجد محادثات أو مجموعات أو أشخاص ظاهرون الآن.',
                                    appearance: appearance,
                                    isDark: isDark,
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
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
                            children: [
                              _HomeSectionHeader(
                                title: 'المحادثات المفضلة',
                                subtitle:
                                    'كل المحادثات التي قمت بتعليمها كمفضلة.',
                                appearance: appearance,
                                isDark: isDark,
                              ),
                              const SizedBox(height: 8),
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
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
                            children: [
                              _HomeSectionHeader(
                                title: 'المحادثات المؤرشفة',
                                subtitle:
                                    'كل المحادثات التي أخفيتها من القائمة الرئيسية.',
                                appearance: appearance,
                                isDark: isDark,
                              ),
                              const SizedBox(height: 8),
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
                        const TicketsScreen(embedded: true),
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
                            padding: const EdgeInsets.fromLTRB(0, 12, 0, 100),
                            children: [
                              _HomeSectionHeader(
                                title: 'الدليل حسب الفروع',
                                subtitle:
                                    'كل الموظفين ظاهرون هنا حسب الفروع التي ينشئها الأدمن.',
                                appearance: appearance,
                                isDark: isDark,
                              ),
                              const SizedBox(height: 8),
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
              );
            },
          ),
        ),
      ),
    );
  }
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
  });

  final String label;
  final ChatResolvedAppearance appearance;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: appearance.accent.withValues(alpha: 0.14),
            child: Icon(Icons.info_outline_rounded, color: appearance.accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
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

    return OpenContainer(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: const Duration(milliseconds: 280),
      closedColor: Colors.transparent,
      openColor: colorScheme.surface,
      closedElevation: 0,
      openElevation: 0,
      openBuilder: (context, _) {
        // If there's an existing conversation, open it directly.
        // Otherwise, open an empty one (requires backend creation, so let the caller handle it).
        // Wait, OpenBuilder requires returning a widget synchronously!
        // We can't await. So if existingConversation == null, we CANNOT use OpenContainer easily!
        return hasConversation
            ? ConversationScreen(conversation: existingConversation!)
            : const SizedBox();
      },
      closedBuilder: (context, openContainer) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: hasConversation ? openContainer : onTap,
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
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
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

  ChatDirectoryUser? _directPeer() {
    for (final member in conversation.members) {
      if (member.id != currentUserId) {
        return member;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final peer = conversation.type == 'direct' ? _directPeer() : null;
    final title = conversation.displayTitle(currentUserId);
    final preview = typingPreviewText ?? _conversationPreview(conversation);
    final accent = _conversationAccent(conversation.type);
    final showPresence = peer != null;
    final colorScheme = Theme.of(context).colorScheme;
    final isBlockedForCurrentUser = conversation.blockedMemberIds.contains(
      currentUserId,
    );
    final isTypingPreview = typingPreviewText != null;

    return OpenContainer(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: const Duration(milliseconds: 280),
      closedColor: Colors.transparent,
      openColor: colorScheme.surface,
      closedElevation: 0,
      openElevation: 0,
      openBuilder: (context, _) =>
          ConversationScreen(conversation: conversation),
      closedBuilder: (context, openContainer) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: openContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        ChatAvatar(
                          radius: 28,
                          backgroundColor: accent.withValues(alpha: 0.14),
                          avatarUrl: peer?.avatarUrl,
                          fallback: Text(
                            peer != null
                                ? _avatarLabel(peer.displayName)
                                : _avatarLabel(title),
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (conversation.isPinned)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 6,
                                  ),
                                  child: Icon(
                                    Icons.push_pin_rounded,
                                    size: 14,
                                    color: accent,
                                  ),
                                ),
                              if (conversation.isFavorite)
                                const Padding(
                                  padding: EdgeInsetsDirectional.only(start: 6),
                                  child: Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: Color(0xFFFFB020),
                                  ),
                                ),
                              if (conversation.isMuted)
                                const Padding(
                                  padding: EdgeInsetsDirectional.only(start: 6),
                                  child: Icon(
                                    Icons.volume_off_rounded,
                                    size: 14,
                                    color: Color(0xFF708499),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                conversation.lastMessage?.createdAt != null
                                    ? formatEgyptTime(
                                        conversation.lastMessage!.createdAt!,
                                      )
                                    : DateFormat('dd/MM').format(
                                        conversation.updatedAt.toLocal(),
                                      ),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isTypingPreview
                                      ? appearance.accent
                                      : colorScheme.onSurfaceVariant,
                                  fontWeight: isTypingPreview
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (!conversation.isActive)
                                const _MetaPill(
                                  icon: Icons.block_outlined,
                                  label: 'معطلة',
                                ),
                              if (!conversation.isActive)
                                const SizedBox(width: 8),
                              if (isBlockedForCurrentUser)
                                const _MetaPill(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'قراءة فقط',
                                ),
                              if (isBlockedForCurrentUser)
                                const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _conversationTypeLabel(conversation.type),
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (showPresence) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _presenceText(peer),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PopupMenuButton<String>(
                          tooltip: 'خيارات المحادثة',
                          onSelected: (value) {
                            switch (value) {
                              case 'pin':
                                onTogglePin();
                                break;
                              case 'mute':
                                onToggleMute();
                                break;
                              case 'favorite':
                                onToggleFavorite();
                                break;
                              case 'delete':
                                onDeleteConversation();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'pin',
                              child: Text(
                                conversation.isPinned
                                    ? 'إزالة التثبيت'
                                    : 'تثبيت المحادثة',
                              ),
                            ),
                            PopupMenuItem(
                              value: 'mute',
                              child: Text(
                                conversation.isMuted
                                    ? 'إلغاء الكتم'
                                    : 'كتم المحادثة',
                              ),
                            ),
                            PopupMenuItem(
                              value: 'favorite',
                              child: Text(
                                conversation.isFavorite
                                    ? 'إزالة من المفضلة'
                                    : 'إضافة إلى المفضلة',
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('مسح/مغادرة/حذف'),
                            ),
                          ],
                          child: Icon(
                            Icons.more_vert_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (conversation.unreadCount > 0) ...[
                          const SizedBox(height: 6),
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: appearance.accent,
                            child: Text(
                              '${conversation.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 80, end: 16),
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: isDark
                      ? const Color(0xFF38383A)
                      : const Color(0xFFC6C6C8),
                ),
              ),
            ],
          ),
        ),
      ),
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
        const PopupMenuItem(
          value: 'updates',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.system_update_alt_rounded),
            title: Text('التحديثات'),
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
                        icon: Icons.system_update_alt_rounded,
                        label: 'التحديثات',
                        onTap: () => onSelected('updates'),
                        iconColor: const Color(0xFF007AFF),
                      ),
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
          'image' => 'صورة',
          'pdf' => 'ملف PDF',
          'audio' => 'ملاحظة صوتية',
          'file' => 'ملف مرفق',
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



