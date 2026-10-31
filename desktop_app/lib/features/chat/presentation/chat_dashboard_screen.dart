import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/models/managed_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/desktop_workspace_sidebar.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../files/presentation/files_dashboard_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../servers/presentation/servers_screen.dart';
import '../../tickets/presentation/tickets_screen.dart';
import '../../updates/presentation/update_center_screen.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../providers/chat_folders_provider.dart';
import 'chat_admin_panel.dart';
import 'chat_appearance.dart';
import 'favorite_messages_screen.dart';
import 'group_management_dialog.dart';
import 'widgets/chat_audio_attachment_player.dart';
import 'widgets/chat_screen.dart';
import 'widgets/chat_sidebar.dart';
import 'widgets/chat_ui_helpers.dart';
import 'widgets/desktop_message_actions_dialogs.dart';
import 'widgets/new_conversation_dialog.dart' as widgets;
import 'widgets/right_panel.dart';


// ─── Telegram-style colour tokens ────────────────────────────────────────────
class _TgColors {
  _TgColors._();

  static const sidebarBg = Color(0xFFFDFEFF);
  static const mainBg = Color(0xFFF8FBFE);
  static const handle = Color(0xFFCACDD2);

  static const sidebarBgDark = Color(0xFF212121);
  static const mainBgDark = Color(0xFF0E1621);
  static const handleDark = Color(0xFF3A3A3A);
}
// ─────────────────────────────────────────────────────────────────────────────

class ChatDashboardScreen extends ConsumerStatefulWidget {
  const ChatDashboardScreen({
    super.key,
    this.openAdminOnStart = false,
    this.openTicketsOnStart = false,
    this.isWrapped = false,
    this.activeSection = DesktopWorkspaceSection.chat,
    this.onSectionChanged,
  });

  final bool openAdminOnStart;
  final bool openTicketsOnStart;
  final bool isWrapped;
  final DesktopWorkspaceSection activeSection;
  final ValueChanged<DesktopWorkspaceSection>? onSectionChanged;

  @override
  ConsumerState<ChatDashboardScreen> createState() =>
      _ChatDashboardScreenState();
}

class _ChatDashboardScreenState extends ConsumerState<ChatDashboardScreen> {
  static const double _compactSidebarWidth = 88;
  static const double _compactSidebarBreakpoint = 270;

  final TextEditingController _sidebarSearchController =
      TextEditingController();
  late final ProviderContainer _container;
  final Map<String, Map<String, String>> _typingByConversationId =
      <String, Map<String, String>>{};
  final Map<String, Timer> _typingPreviewTimers = <String, Timer>{};
  StreamSubscription<ChatSocketEvent>? _chatEventsSubscription;

  ChatSidebarFilter _sidebarFilter = ChatSidebarFilter.all;
  String? _selectedConversationId;
  bool _showRightPanel = false;
  bool _showAdminPanel = false;
  bool _showTicketsPanel = false;
  bool _showClosedTicketsPanel = false;
  TicketTypeTab _activeTicketTab = TicketTypeTab.ticket;
  double _sidebarWidth = 300;
  double _rightPanelWidth = 320;
  int _searchSignal = 0;
  int _adminTabIndex = 0;
  String? _targetMessageId;
  int _targetMessageSignal = 0;
  void _syncSectionFromWidget() {
    final shouldShowAdmin =
        widget.activeSection == DesktopWorkspaceSection.admin;
    final shouldShowTickets =
        widget.activeSection == DesktopWorkspaceSection.tickets;

    if (_showAdminPanel == shouldShowAdmin &&
        _showTicketsPanel == shouldShowTickets) {
      return;
    }

    setState(() {
      _showAdminPanel = shouldShowAdmin;
      _showTicketsPanel = shouldShowTickets;
      _showClosedTicketsPanel = false;

      if (_showAdminPanel || _showTicketsPanel) {
        _showRightPanel = false;
        _selectedConversationId = null;
      }
    });

    if (shouldShowAdmin || shouldShowTickets) {
      _setActiveConversation(null);
    }
  }

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _showAdminPanel = widget.openAdminOnStart;
    _showTicketsPanel = !widget.openAdminOnStart && widget.openTicketsOnStart;
    _sidebarSearchController.addListener(_onSearchChanged);
    desktopJumpToMessageNotifier.addListener(_onJumpToMessageRequested);
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
            _scheduleTypingPreviewExpiry(conversationId, typingUserId);
            return;
          case 'stop_typing':
            final typingUserId = _extractTypingUserId(event.payload);
            if (typingUserId == null) {
              return;
            }
            _clearTypingPreviewTimer(conversationId, typingUserId);
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
              _clearTypingPreviewTimersForConversation(conversationId);
              setState(() {
                _typingByConversationId.remove(conversationId);
              });
            }
            return;
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionFromWidget();
    });
  }

  @override
  void didUpdateWidget(covariant ChatDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.activeSection != widget.activeSection) {
      _syncSectionFromWidget();
    }
  }

  @override
  void dispose() {
    desktopJumpToMessageNotifier.removeListener(_onJumpToMessageRequested);
    _chatEventsSubscription?.cancel();
    for (final timer in _typingPreviewTimers.values) {
      timer.cancel();
    }
    _typingPreviewTimers.clear();
    _sidebarSearchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onJumpToMessageRequested() {
    final target = desktopJumpToMessageNotifier.value;
    if (target == null || !mounted) return;
    desktopJumpToMessageNotifier.value = null;

    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    if (overview == null) return;
    ChatConversation? targetConv;
    for (final c in overview.conversations) {
      if (c.id == target.conversationId) {
        targetConv = c;
        break;
      }
    }
    if (targetConv != null) {
      _selectConversation(
        targetConv,
        targetMessageId: target.messageId,
      );
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
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

  String _typingTimerKey(String conversationId, String userId) {
    return '$conversationId:$userId';
  }

  void _scheduleTypingPreviewExpiry(String conversationId, String userId) {
    final key = _typingTimerKey(conversationId, userId);
    _typingPreviewTimers[key]?.cancel();
    _typingPreviewTimers[key] = Timer(const Duration(seconds: 4), () {
      _typingPreviewTimers.remove(key);
      if (!mounted) {
        return;
      }
      setState(() {
        final entry = _typingByConversationId[conversationId];
        entry?.remove(userId);
        if (entry == null || entry.isEmpty) {
          _typingByConversationId.remove(conversationId);
        }
      });
    });
  }

  void _clearTypingPreviewTimer(String conversationId, String userId) {
    final key = _typingTimerKey(conversationId, userId);
    _typingPreviewTimers.remove(key)?.cancel();
  }

  void _clearTypingPreviewTimersForConversation(String conversationId) {
    final prefix = '$conversationId:';
    final keys = _typingPreviewTimers.keys
        .where((entry) => entry.startsWith(prefix))
        .toList();
    for (final key in keys) {
      _typingPreviewTimers.remove(key)?.cancel();
    }
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

  void _setActiveConversation(String? id) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final notifier = _container.read(activeConversationIdProvider.notifier);

      if (notifier.state != id) {
        notifier.state = id;
      }
    });
  }

  void _selectConversation(
    ChatConversation? conversation, {
    bool openInfoPanel = false,
    String? targetMessageId,
  }) {
    setState(() {
      _selectedConversationId = conversation?.id;
      _targetMessageId = targetMessageId;
      if (targetMessageId != null) {
        _targetMessageSignal++;
      }
      _showAdminPanel = false;
      _showTicketsPanel = false;
      if (conversation == null) {
        _showRightPanel = false;
      } else if (openInfoPanel) {
        _showRightPanel = true;
      }
    });

    _setActiveConversation(conversation?.id);

    if (conversation != null) {
      widget.onSectionChanged?.call(DesktopWorkspaceSection.chat);
    }
  }

  void _openFiles() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FilesDashboardScreen()),
    );
  }

  void _openServers() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const ServersScreen()));
  }

  void _openProfile() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  Future<void> _openFavoriteMessages() async {
    final result = await Navigator.of(context).push<FavoriteMessageSelectionResult>(
      MaterialPageRoute(builder: (_) => const FavoriteMessagesScreen()),
    );
    if (!mounted || result == null) {
      return;
    }
    _selectConversation(
      result.conversation,
      targetMessageId: result.targetMessageId,
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
    _selectConversation(conversation);
  }

  // ── Create dialog ──────────────────────────────────────────────────────────
  Future<void> _showCreateDialog({
    required AppUser currentUser,
    required ChatOverviewData overview,
  }) async {
    final createdConversation = await showDialog<ChatConversation>(
      context: context,
      builder: (context) => widgets.NewConversationDialog(
        currentUser: currentUser,
        overview: overview,
      ),
    );

    if (createdConversation != null && mounted) {
      _selectConversation(createdConversation);
    }
  }

  // ── Preferences / delete / group ──────────────────────────────────────────
  Future<void> _updateConversationPreferences(
    ChatConversation conversation, {
    bool? isPinned,
    bool? isMuted,
    bool? isArchived,
    bool? isFavorite,
  }) async {
    try {
      await ref
          .read(chatOverviewControllerProvider.notifier)
          .updateConversationPreferences(
            conversationId: conversation.id,
            isPinned: isPinned,
            isMuted: isMuted,
            isArchived: isArchived,
            isFavorite: isFavorite,
          );
    } catch (error) {
      final text = error.toString().toLowerCase();
      final notFound =
          text.contains('conversation not found') ||
          text.contains('404') ||
          text.contains('غير موجود');
      if (notFound) {
        if (!mounted) return;
        if (_selectedConversationId == conversation.id) {
          _selectConversation(null);
        }
        return;
      }
      if (!mounted) return;
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
              subtitle: const Text('إزالة المحادثة ومسح رسائلها من جهازك'),
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
                subtitle: const Text('يحذف المحادثة بالكامل من كل الأطراف'),
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
      final overviewController = ref.read(
        chatOverviewControllerProvider.notifier,
      );
      if (action == 'leave') {
        await overviewController.leaveConversation(conversation.id);
        if (!mounted) return;
        if (_selectedConversationId == conversation.id) {
          _selectConversation(null);
        }
        return;
      }

      if (action == 'clear') {
        await overviewController.clearConversationMessages(conversation.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم مسح الرسائل بنجاح')));
        }
        return;
      }

      if (action == 'self') {
        if (!mounted) return;
        final shouldDeleteSelf = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
        if (shouldDeleteSelf != true) return;
        await overviewController.deleteConversation(conversation.id);
        if (!mounted) return;
        if (_selectedConversationId == conversation.id) {
          _selectConversation(null);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المحادثة من قائمتك')),
        );
        return;
      }

      if (action == 'global') {
        if (!mounted) return;
        final shouldDeleteGlobal = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
        if (shouldDeleteGlobal != true) {
          return;
        }
        await overviewController.deleteConversation(
          conversation.id,
          deleteForEveryone: true,
        );
        if (!mounted) return;
        if (_selectedConversationId == conversation.id) {
          _selectConversation(null);
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم الحذف النهائي بنجاح')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openGroupManagement(ChatConversation conversation) async {
    final updated = await showDialog<ChatConversation>(
      context: context,
      builder: (context) => GroupManagementDialog(conversation: conversation),
    );
    if (updated == null || !mounted) return;
    await ref.read(chatOverviewControllerProvider.notifier).refresh();
    _selectConversation(updated, openInfoPanel: true);
  }

  // ── Filtering ──────────────────────────────────────────────────────────────
  List<ChatConversation> _visibleConversations(
    List<ChatConversation> source,
    String currentUserId,
  ) {
    final query = _sidebarSearchController.text.trim().toLowerCase();
    final byType = source
        .where(
          (c) => switch (_sidebarFilter) {
            ChatSidebarFilter.all => true,
            ChatSidebarFilter.direct => c.type == 'direct',
            ChatSidebarFilter.departments => c.type == 'department',
            ChatSidebarFilter.branches => false,
            ChatSidebarFilter.rooms =>
              c.type == 'group' || c.type == 'broadcast',
            ChatSidebarFilter.favorites => c.isFavorite,
            ChatSidebarFilter.archived => c.isArchived,
          },
        )
        .toList();

    final searched = byType.where((c) {
      if (query.isEmpty) return true;
      final title = c.displayTitle(currentUserId).toLowerCase();
      final preview = (c.lastMessage?.content ?? '').toLowerCase();
      return title.contains(query) || preview.contains(query);
    }).toList();

    return sortConversationsForSidebar(searched);
  }

  void _ensureSelection({required List<ChatConversation> allConversations}) {
    final selectedExists =
        _selectedConversationId != null &&
        allConversations.any((c) => c.id == _selectedConversationId);

    if (_selectedConversationId != null && !selectedExists) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectConversation(null);
      });
      return;
    }

    if (_showAdminPanel || _showTicketsPanel) return;
  }

  ChatConversation? _selectedConversation(
    List<ChatConversation> allConversations,
  ) {
    if (_selectedConversationId == null) return null;
    return allConversations
        .where((c) => c.id == _selectedConversationId)
        .firstOrNull;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final authToken = ref.watch(authTokenProvider).valueOrNull;
    final usersState = ref.watch(usersControllerProvider);
    final chatState = ref.watch(chatOverviewControllerProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    ref.watch(desktopMessageRemindersProvider);
    final isDark = themeMode == ThemeMode.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final chatPreferences =
        authUser?.chatPreferences ?? ChatPreferences.defaults;
    final appearance = ChatAppearanceCatalog.resolveAppearance(
      preferences: chatPreferences,
      isDark: isDark,
      colorScheme: colorScheme,
    );
    final shellBackdropColor = Color.lerp(
      appearance.wallpaperColors.last,
      isDark ? _TgColors.mainBgDark : colorScheme.surfaceContainerLowest,
      isDark ? 0.18 : 0.88,
    )!;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true): _NewIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _EscIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) {
              if (_selectedConversationId != null &&
                  !_showAdminPanel &&
                  !_showTicketsPanel) {
                setState(() => _searchSignal++);
              }
              return null;
            },
          ),
          _NewIntent: CallbackAction<_NewIntent>(
            onInvoke: (_) async {
              final data = ref.read(chatOverviewControllerProvider).valueOrNull;
              final currentUser = ref.read(authControllerProvider).valueOrNull;
              if (data != null && currentUser != null) {
                await _showCreateDialog(
                  currentUser: currentUser,
                  overview: data,
                );
              }
              return null;
            },
          ),
          _EscIntent: CallbackAction<_EscIntent>(
            onInvoke: (_) {
              if (_showRightPanel) setState(() => _showRightPanel = false);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: shellBackdropColor,
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final overview = chatState.valueOrNull;
                        if (overview != null) {
                          final allConversations = sortConversationsForSidebar(
                            overview.conversations,
                          );
                          final visibleConversations = _visibleConversations(
                            allConversations,
                            authUser?.id ?? '',
                          );
                          _ensureSelection(allConversations: allConversations);
                          final selectedConversation = _selectedConversation(
                            allConversations,
                          );

                          return _buildTelegramShell(
                            authUser: authUser,
                            authToken: authToken,
                            usersState: usersState,
                            overview: overview,
                            appearance: appearance,
                            themeMode: themeMode,
                            isDark: isDark,
                            visibleConversations: visibleConversations,
                            selectedConversation: selectedConversation,
                          );
                        }

                        if (chatState.hasError) {
                          return Center(
                            child: Text(chatState.error.toString()),
                          );
                        }

                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ShimmerSkeleton(width: 180, height: 14),
                                SizedBox(height: 10),
                                ShimmerSkeleton(width: 240, height: 12),
                              ],
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
        ),
      ),
    );
  }

  // ── Telegram shell ─────────────────────────────────────────────────────────
  Widget _buildTelegramShell({
    required AppUser? authUser,
    required String? authToken,
    required AsyncValue<List<ManagedUser>> usersState,
    required ChatOverviewData overview,
    required ChatResolvedAppearance appearance,
    required ThemeMode themeMode,
    required bool isDark,
    required List<ChatConversation> visibleConversations,
    required ChatConversation? selectedConversation,
  }) {
    final sidebarBg = Color.lerp(
      appearance.wallpaperColors.last,
      isDark ? _TgColors.sidebarBgDark : _TgColors.sidebarBg,
      isDark ? 0.30 : 0.90,
    )!;
    final mainBg = Color.lerp(
      appearance.wallpaperColors.first,
      isDark ? _TgColors.mainBgDark : _TgColors.mainBg,
      isDark ? 0.22 : 0.94,
    )!;
    final handleClr = isDark ? _TgColors.handleDark : _TgColors.handle;
    final horizontalDirection = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    final forcedCompactSidebar = _showAdminPanel || _showTicketsPanel;
    final autoCompactSidebar =
        !forcedCompactSidebar && _sidebarWidth <= _compactSidebarBreakpoint;
    final sidebarCollapsed = forcedCompactSidebar || autoCompactSidebar;
    final sidebarWidth = sidebarCollapsed
        ? _compactSidebarWidth
        : _sidebarWidth;
    final activeSection = _showAdminPanel
        ? DesktopWorkspaceSection.admin
        : _showTicketsPanel
        ? DesktopWorkspaceSection.tickets
        : DesktopWorkspaceSection.chat;
    final appServerDefaults = ref.watch(appServerDefaultsProvider).valueOrNull;
    final cachedAppServerDefaults = ref
        .watch(cachedAppServerDefaultsProvider)
        .valueOrNull;
    final showServersShortcut =
        (appServerDefaults ?? cachedAppServerDefaults)?.showServersShortcut ??
        false;

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              // ── Sidebar ────────────────────────────────────────────────────────
              // authUser?.role == 'admin'
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: sidebarWidth,
                decoration: BoxDecoration(
                  color: sidebarBg,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.08,
                      ),
                      blurRadius: 8,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: ChatSidebar(
                  currentUser: authUser,
                  compact: sidebarCollapsed,
                  currentThemeMode: themeMode,
                  searchController: _sidebarSearchController,
                  currentFilter: _sidebarFilter,
                  conversations: visibleConversations,
                  overview: overview,
                  currentUserId: authUser?.id ?? '',
                  typingPreviewByConversationId: {
                    for (final conversation in visibleConversations)
                      if (_typingPreviewText(conversation) case final preview?)
                        conversation.id: preview,
                  },
                  selectedConversationId: _selectedConversationId,
                  onFilterChanged: (filter) =>
                      setState(() => _sidebarFilter = filter),
                  onConversationSelected: _selectConversation,
                  onOpenOrStartDirectConversation: (user) {
                    _openOrStartDirectConversation(
                      user,
                      overview,
                      authUser?.id ?? '',
                    );
                  },
                  onCreateConversation: () async {
                    if (authUser == null) return;
                    await _showCreateDialog(
                      currentUser: authUser,
                      overview: overview,
                    );
                  },
                  onRefresh: () async {
                    if (!mounted) return;
                    final overviewCtrl = ref.read(
                      chatOverviewControllerProvider.notifier,
                    );
                    final foldersCtrl = ref.read(chatFoldersProvider.notifier);
                    await overviewCtrl.refresh();
                    await foldersCtrl.refresh();
                  },
                  onOpenAdmin: () {
                    setState(() {
                      _showAdminPanel = true;
                      _showTicketsPanel = false;
                      _showRightPanel = false;
                      _selectedConversationId = null;
                    });
                    _setActiveConversation(null);
                    widget.onSectionChanged?.call(
                      DesktopWorkspaceSection.admin,
                    );
                  },

                  onOpenTickets: () {
                    setState(() {
                      _showTicketsPanel = true;
                      _showClosedTicketsPanel = false;
                      _showAdminPanel = false;
                      _showRightPanel = false;
                      _selectedConversationId = null;
                    });
                    _setActiveConversation(null);
                    widget.onSectionChanged?.call(
                      DesktopWorkspaceSection.tickets,
                    );
                  },
                  onOpenFiles: _openFiles,
                  onOpenServers: _openServers,
                  onOpenProfile: _openProfile,
                  onOpenFavoriteMessages: _openFavoriteMessages,
                  onToggleTheme: () => ref
                      .read(themeModeControllerProvider.notifier)
                      .cycleThemeMode(),
                  onTogglePin: (c) =>
                      _updateConversationPreferences(c, isPinned: !c.isPinned),
                  onToggleMute: (c) => _updateConversationPreferences(
                    c,
                    isMuted: !c.isCurrentlyMuted,
                  ),
                  onToggleArchive: (c) => _updateConversationPreferences(
                    c,
                    isArchived: !c.isArchived,
                  ),
                  onToggleFavorite: (c) => _updateConversationPreferences(
                    c,
                    isFavorite: !c.isFavorite,
                  ),
                  onDeleteConversation: _deleteConversation,
                ),
              ),

              // ── Resize handle ──────────────────────────────────────────────────
              forcedCompactSidebar
                  ? Container(
                      width: 1,
                      color: handleClr.withValues(alpha: 0.35),
                    )
                  : _ResizeHandle(
                      color: handleClr,
                      onDrag: (delta) => setState(() {
                        _sidebarWidth =
                            (_sidebarWidth +
                                    (delta.delta.dx * horizontalDirection))
                                .clamp(250, 420);
                      }),
                    ),

              if (_showTicketsPanel)
                Container(
                  width: sidebarCollapsed ? 92 : 220,
                  decoration: BoxDecoration(
                    color: sidebarBg,
                    border: Border(
                      left: BorderSide(
                        color: handleClr.withValues(alpha: 0.32),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!sidebarCollapsed)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          child: Text(
                            'أقسام التذاكر',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      const Divider(height: 1),
                      for (final tab in TicketTypeTab.values) ...[
                        _TicketSectionButton(
                          label: tab.label,
                          icon: tab.icon,
                          selected: _activeTicketTab == tab,
                          collapsed: sidebarCollapsed,
                          onTap: () {
                            setState(() {
                              _activeTicketTab = tab;
                              _showClosedTicketsPanel = false;
                            });
                          },
                        ),
                        const Divider(height: 1),
                      ],
                      _TicketSectionButton(
                        label: 'التذاكر المغلقة',
                        icon: Icons.lock_outline_rounded,
                        selected: _showClosedTicketsPanel,
                        collapsed: sidebarCollapsed,
                        onTap: () {
                          setState(() => _showClosedTicketsPanel = true);
                        },
                      ),
                      const Divider(height: 1),
                    ],
                  ),
                ),

              // ── Main area ──────────────────────────────────────────────────────
              Expanded(
                child: ColoredBox(
                  color: mainBg,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.02, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _showAdminPanel
                        ? ChatAdminPanel(
                            key: const ValueKey('admin_panel'),
                            departments: overview.departments,
                            branches: overview.branches,
                            manageableConversations:
                                overview.manageableConversations,
                            users: overview.users,
                            roles: overview.roles,
                            usersState: usersState,
                            currentUser: authUser!,
                            initialTabIndex: _adminTabIndex,
                            onTabChanged: (index) {
                              _adminTabIndex = index;
                            },
                          )
                        : _showTicketsPanel
                        ? TicketsScreen(
                            key: const ValueKey('tickets_panel'),
                            embedded: true,
                            closedOnly: _showClosedTicketsPanel,
                            initialTab: _activeTicketTab,
                            onTabChanged: (tab) {
                              setState(() => _activeTicketTab = tab);
                            },
                          )
                        : selectedConversation == null
                        ? Column(
                            children: [
                              const DesktopDueReminderBanner(),
                              GlobalDesktopMiniAudioPlayerBar(
                                onTapSession: (session) {
                                  if (session.message.conversationId
                                      .isNotEmpty) {
                                    desktopJumpToMessageNotifier.value = (
                                      conversationId:
                                          session.message.conversationId,
                                      messageId: session.message.id,
                                    );
                                  }
                                },
                              ),
                              const Expanded(child: _TelegramEmptyState()),
                            ],
                          )
                        : ChatScreen(
                            key: ValueKey(
                              'chat_${selectedConversation.id}_$_targetMessageSignal',
                            ),
                            conversation: selectedConversation,
                            currentUser: authUser,
                            token: authToken,
                            initialTargetMessageId: _targetMessageId,
                            searchSignal: _searchSignal,
                            rightPanelVisible: _showRightPanel,
                            onToggleRightPanel: () => setState(
                              () => _showRightPanel = !_showRightPanel,
                            ),
                            onCloseConversation: () =>
                                _selectConversation(null),
                            onConversationDeleted: () {
                              if (_selectedConversationId ==
                                  selectedConversation.id) {
                                _selectConversation(null);
                              }
                            },
                          ),
                  ),
                ),
              ),

              // ── Right panel ────────────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => SizeTransition(
                  axis: Axis.horizontal,
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: child,
                ),
                child:
                    !_showAdminPanel &&
                        !_showTicketsPanel &&
                        _showRightPanel &&
                        selectedConversation != null
                    ? Row(
                        key: ValueKey('right_${selectedConversation.id}'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ResizeHandle(
                            color: handleClr,
                            onDrag: (delta) => setState(() {
                              _rightPanelWidth =
                                  (_rightPanelWidth -
                                          (delta.delta.dx *
                                              horizontalDirection))
                                      .clamp(280, 480);
                            }),
                          ),
                          Container(
                            width: _rightPanelWidth,
                            decoration: BoxDecoration(
                              color: sidebarBg,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.3 : 0.08,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(-2, 0),
                                ),
                              ],
                            ),
                            child: RightPanel(
                              conversation: selectedConversation,
                              currentUser: authUser,
                              onClose: () =>
                                  setState(() => _showRightPanel = false),
                              onTogglePinned: () =>
                                  _updateConversationPreferences(
                                    selectedConversation,
                                    isPinned: !selectedConversation.isPinned,
                                  ),
                              onToggleMuted: () =>
                                  _updateConversationPreferences(
                                    selectedConversation,
                                    isMuted:
                                        !selectedConversation.isCurrentlyMuted,
                                  ),
                              onToggleArchived: () =>
                                  _updateConversationPreferences(
                                    selectedConversation,
                                    isArchived:
                                        !selectedConversation.isArchived,
                                  ),
                              onDeleteConversation: () =>
                                  _deleteConversation(selectedConversation),
                              onOpenGroupManagement: () =>
                                  _openGroupManagement(selectedConversation),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('right_closed')),
              ),
            ],
          ),
        ),
        if (!widget.isWrapped)
          DesktopWorkspaceSidebar(
            user: authUser,
            activeSection: activeSection,
            currentThemeMode: themeMode,
            isDark: isDark,
            accentColor: Theme.of(context).colorScheme.primary,
            onOpenChat: () {
              setState(() {
                _showAdminPanel = false;
                _showTicketsPanel = false;
              });
              widget.onSectionChanged?.call(DesktopWorkspaceSection.chat);
            },
            onRefresh: () =>
                ref.read(chatOverviewControllerProvider.notifier).refresh(),
            onOpenFiles: _openFiles,
            showServersShortcut: showServersShortcut,
            onOpenServers: _openServers,
            onOpenProfile: _openProfile,
            onOpenUpdates: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UpdateCenterScreen()),
            ),
            onToggleTheme: () =>
                ref.read(themeModeControllerProvider.notifier).cycleThemeMode(),
            onOpenTickets: () {
              setState(() {
                _showTicketsPanel = true;
                _showAdminPanel = false;
                _showRightPanel = false;
                _selectedConversationId = null;
              });
              _setActiveConversation(null);
              widget.onSectionChanged?.call(DesktopWorkspaceSection.tickets);
            },
            onLogout: () => ref.read(authControllerProvider.notifier).logout(),
            onCreateConversation: authUser == null
                ? null
                : () => _showCreateDialog(
                    currentUser: authUser,
                    overview: overview,
                  ),
            onOpenAdmin: () {
              setState(() {
                _showAdminPanel = true;
                _showTicketsPanel = false;
                _showRightPanel = false;
                _selectedConversationId = null;
              });
              _setActiveConversation(null);
              widget.onSectionChanged?.call(DesktopWorkspaceSection.admin);
            },
          ),
      ],
    );
  }
}

// ── Resize handle ──────────────────────────────────────────────────────────────
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag, this.color});

  final ValueChanged<DragUpdateDetails> onDrag;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: onDrag,
        child: SizedBox(
          width: 5,
          child: Center(
            child: Container(
              width: 1,
              height: 40,
              color:
                  color ??
                  Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketSectionButton extends StatelessWidget {
  const _TicketSectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: selected
            ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, color: color),
            if (!collapsed) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────
class _TelegramEmptyState extends StatelessWidget {
  const _TelegramEmptyState();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4FAAFF), Color(0xFF2071CD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3390EC).withValues(alpha: 0.55),
                  blurRadius: 100,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50.0),
              ),
              child: Image.asset("assets/images/logo.png"),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'اختر محادثة',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1C2B3A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اختر من محادثاتك الموجودة،\nأو اضغط Ctrl + N لبدء محادثة جديدة.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white54 : const Color(0xFF708499),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: const [
              _ShortcutChip(label: 'Ctrl + N', hint: 'محادثة جديدة'),
              _ShortcutChip(label: 'Ctrl + F', hint: 'بحث'),
              _ShortcutChip(label: 'Esc', hint: 'إغلاق اللوحة'),
            ],
          ),
          SizedBox(height: 50.0),
          Text(
            'Copyright © 2026 Yousef Mohamed',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white54 : const Color(0xFF708499),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  const _ShortcutChip({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFF3390EC).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isDark ? Colors.white70 : const Color(0xFF3390EC),
          ),
          children: [
            TextSpan(
              text: label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: '  $hint'),
          ],
        ),
      ),
    );
  }
}

// ── Intents ────────────────────────────────────────────────────────────────────
class _SearchIntent extends Intent {
  const _SearchIntent();
}

class _NewIntent extends Intent {
  const _NewIntent();
}

class _EscIntent extends Intent {
  const _EscIntent();
}
