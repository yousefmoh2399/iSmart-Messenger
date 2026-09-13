// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';

// import '../../../shared/models/app_user.dart';
// import '../../../shared/models/managed_user.dart';
// import '../../../shared/providers/providers.dart';
// import '../models/chat_models.dart';
// import 'chat_admin_panel.dart';
// import 'group_management_dialog.dart';
// import 'widgets/chat_screen.dart';
// import 'widgets/chat_sidebar.dart';
// import 'widgets/chat_ui_helpers.dart';
// import 'widgets/right_panel.dart';

// class ChatDashboardScreen extends ConsumerStatefulWidget {
//   const ChatDashboardScreen({super.key});

//   @override
//   ConsumerState<ChatDashboardScreen> createState() =>
//       _ChatDashboardScreenState();
// }

// class _ChatDashboardScreenState extends ConsumerState<ChatDashboardScreen> {
//   final TextEditingController _sidebarSearchController =
//       TextEditingController();

//   ChatSidebarFilter _sidebarFilter = ChatSidebarFilter.all;
//   String? _selectedConversationId;
//   bool _showRightPanel = false;
//   bool _showAdminPanel = false;
//   double _sidebarWidth = 300;
//   double _rightPanelWidth = 320;
//   int _searchSignal = 0;

//   @override
//   void initState() {
//     super.initState();
//     _sidebarSearchController.addListener(_onSearchChanged);
//   }

//   @override
//   void dispose() {
//     _sidebarSearchController
//       ..removeListener(_onSearchChanged)
//       ..dispose();
//     super.dispose();
//   }

//   void _onSearchChanged() {
//     if (mounted) {
//       setState(() {});
//     }
//   }

//   void _setActiveConversation(String? conversationId) {
//     Future<void>.microtask(() {
//       if (!mounted) {
//         return;
//       }
//       ref.read(activeConversationIdProvider.notifier).state = conversationId;
//     });
//   }

//   void _selectConversation(
//     ChatConversation? conversation, {
//     bool openInfoPanel = false,
//   }) {
//     setState(() {
//       _selectedConversationId = conversation?.id;
//       _showAdminPanel = false;
//       if (conversation == null) {
//         _showRightPanel = false;
//       } else if (openInfoPanel) {
//         _showRightPanel = true;
//       }
//     });
//     _setActiveConversation(conversation?.id);
//   }

//   Future<void> _showCreateDialog({
//     required AppUser currentUser,
//     required ChatOverviewData overview,
//   }) async {
//     final nameController = TextEditingController();
//     final descriptionController = TextEditingController();
//     final selectedMembers = <String>{};
//     String? selectedDirectUserId;
//     String? departmentId = currentUser.departmentId;

//     final availableTypes = <String>[
//       'direct',
//       'group',
//       if (currentUser.can('canCreateRooms')) 'department',
//       if (currentUser.can('canSendBroadcast')) 'broadcast',
//     ];
//     var selectedType = availableTypes.first;

//     final createdConversation = await showDialog<ChatConversation>(
//       context: context,
//       builder: (context) => StatefulBuilder(
//         builder: (context, setDialogState) => AlertDialog(
//           title: const Text('New conversation'),
//           content: SizedBox(
//             width: 520,
//             child: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   DropdownButtonFormField<String>(
//                     initialValue: selectedType,
//                     decoration: const InputDecoration(labelText: 'Type'),
//                     items: availableTypes
//                         .map(
//                           (type) => DropdownMenuItem<String>(
//                             value: type,
//                             child: Text(switch (type) {
//                               'direct' => 'Direct',
//                               'department' => 'Department room',
//                               'broadcast' => 'Broadcast channel',
//                               _ => 'Group',
//                             }),
//                           ),
//                         )
//                         .toList(),
//                     onChanged: (value) {
//                       setDialogState(() {
//                         selectedType = value ?? selectedType;
//                       });
//                     },
//                   ),
//                   const SizedBox(height: 12),
//                   if (selectedType == 'direct') ...[
//                     DropdownButtonFormField<String>(
//                       initialValue: selectedDirectUserId,
//                       decoration: const InputDecoration(
//                         labelText: 'Choose user',
//                       ),
//                       items: overview.users
//                           .where((user) => user.id != currentUser.id)
//                           .map(
//                             (user) => DropdownMenuItem<String>(
//                               value: user.id,
//                               child: Text(user.displayName),
//                             ),
//                           )
//                           .toList(),
//                       onChanged: (value) {
//                         setDialogState(() => selectedDirectUserId = value);
//                       },
//                     ),
//                   ] else ...[
//                     TextField(
//                       controller: nameController,
//                       decoration: const InputDecoration(
//                         labelText: 'Conversation name',
//                       ),
//                     ),
//                     const SizedBox(height: 12),
//                     TextField(
//                       controller: descriptionController,
//                       minLines: 1,
//                       maxLines: 3,
//                       decoration: const InputDecoration(
//                         labelText: 'Description (optional)',
//                       ),
//                     ),
//                     if (selectedType == 'department') ...[
//                       const SizedBox(height: 12),
//                       DropdownButtonFormField<String>(
//                         initialValue: departmentId,
//                         decoration: const InputDecoration(
//                           labelText: 'Department',
//                         ),
//                         items: overview.departments
//                             .map(
//                               (department) => DropdownMenuItem<String>(
//                                 value: department.id,
//                                 child: Text(department.name),
//                               ),
//                             )
//                             .toList(),
//                         onChanged: (value) {
//                           setDialogState(() => departmentId = value);
//                         },
//                       ),
//                     ],
//                     if (selectedType == 'group') ...[
//                       const SizedBox(height: 14),
//                       Text(
//                         'Members',
//                         style: Theme.of(context).textTheme.titleSmall?.copyWith(
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                       const SizedBox(height: 6),
//                       ...overview.users
//                           .where((user) => user.id != currentUser.id)
//                           .map(
//                             (user) => CheckboxListTile(
//                               value: selectedMembers.contains(user.id),
//                               contentPadding: EdgeInsets.zero,
//                               title: Text(user.displayName),
//                               subtitle: Text(user.username),
//                               onChanged: (value) {
//                                 setDialogState(() {
//                                   if (value == true) {
//                                     selectedMembers.add(user.id);
//                                   } else {
//                                     selectedMembers.remove(user.id);
//                                   }
//                                 });
//                               },
//                             ),
//                           ),
//                     ],
//                   ],
//                 ],
//               ),
//             ),
//           ),
//           actions: [
//             TextButton(
//               onPressed: () => Navigator.of(context).pop(),
//               child: const Text('Cancel'),
//             ),
//             FilledButton(
//               onPressed: () async {
//                 final controller = ref.read(
//                   chatOverviewControllerProvider.notifier,
//                 );
//                 ChatConversation conversation;
//                 if (selectedType == 'direct') {
//                   if (selectedDirectUserId == null ||
//                       selectedDirectUserId!.isEmpty) {
//                     return;
//                   }
//                   conversation = await controller.createDirectConversation(
//                     selectedDirectUserId!,
//                   );
//                 } else {
//                   conversation = await controller.createConversation(
//                     type: selectedType,
//                     name: nameController.text.trim(),
//                     description: descriptionController.text.trim(),
//                     memberIds: selectedMembers.toList(),
//                     departmentId: departmentId,
//                   );
//                 }
//                 if (!context.mounted) {
//                   return;
//                 }
//                 Navigator.of(context).pop(conversation);
//               },
//               child: const Text('Create'),
//             ),
//           ],
//         ),
//       ),
//     );

//     if (createdConversation != null && mounted) {
//       _selectConversation(createdConversation);
//     }
//   }

//   Future<void> _updateConversationPreferences(
//     ChatConversation conversation, {
//     bool? isPinned,
//     bool? isMuted,
//     bool? isArchived,
//   }) async {
//     try {
//       await ref
//           .read(chatOverviewControllerProvider.notifier)
//           .updateConversationPreferences(
//             conversationId: conversation.id,
//             isPinned: isPinned,
//             isMuted: isMuted,
//             isArchived: isArchived,
//           );
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(error.toString())));
//     }
//   }

//   Future<void> _deleteConversation(ChatConversation conversation) async {
//     final shouldDelete = await showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Delete conversation'),
//         content: const Text(
//           'This will permanently delete all messages in this conversation.',
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop(false),
//             child: const Text('Cancel'),
//           ),
//           FilledButton(
//             onPressed: () => Navigator.of(context).pop(true),
//             child: const Text('Delete'),
//           ),
//         ],
//       ),
//     );

//     if (shouldDelete != true) {
//       return;
//     }

//     try {
//       await ref
//           .read(chatOverviewControllerProvider.notifier)
//           .deleteConversation(conversation.id);
//       if (!mounted) {
//         return;
//       }
//       if (_selectedConversationId == conversation.id) {
//         _selectConversation(null);
//       }
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(error.toString())));
//     }
//   }

//   Future<void> _openGroupManagement(ChatConversation conversation) async {
//     final updatedConversation = await showDialog<ChatConversation>(
//       context: context,
//       builder: (context) => GroupManagementDialog(conversation: conversation),
//     );
//     if (updatedConversation == null || !mounted) {
//       return;
//     }
//     await ref.read(chatOverviewControllerProvider.notifier).refresh();
//     _selectConversation(updatedConversation, openInfoPanel: true);
//   }

//   List<ChatConversation> _visibleConversations(
//     List<ChatConversation> source,
//     String currentUserId,
//   ) {
//     final query = _sidebarSearchController.text.trim().toLowerCase();
//     final filteredByType = source.where((conversation) {
//       return switch (_sidebarFilter) {
//         ChatSidebarFilter.all => true,
//         ChatSidebarFilter.direct => conversation.type == 'direct',
//         ChatSidebarFilter.departments => conversation.type == 'department',
//         ChatSidebarFilter.rooms =>
//           conversation.type == 'group' || conversation.type == 'broadcast',
//       };
//     }).toList();

//     final searched = filteredByType.where((conversation) {
//       if (query.isEmpty) {
//         return true;
//       }
//       final title = conversation.displayTitle(currentUserId).toLowerCase();
//       final preview = (conversation.lastMessage?.content ?? '').toLowerCase();
//       return title.contains(query) || preview.contains(query);
//     }).toList();

//     return sortConversationsForSidebar(searched);
//   }

//   void _ensureSelection({
//     required List<ChatConversation> allConversations,
//     required List<ChatConversation> visibleConversations,
//   }) {
//     final selectedExists =
//         _selectedConversationId != null &&
//         allConversations.any(
//           (conversation) => conversation.id == _selectedConversationId,
//         );

//     if (_selectedConversationId != null && !selectedExists) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!mounted) {
//           return;
//         }
//         _selectConversation(null);
//       });
//       return;
//     }

//     if (_showAdminPanel) {
//       return;
//     }

//     if (_selectedConversationId == null && visibleConversations.isNotEmpty) {
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!mounted || _selectedConversationId != null) {
//           return;
//         }
//         _selectConversation(visibleConversations.first);
//       });
//     }
//   }

//   ChatConversation? _selectedConversation(
//     List<ChatConversation> allConversations,
//   ) {
//     if (_selectedConversationId == null) {
//       return null;
//     }
//     return allConversations
//         .where((conversation) => conversation.id == _selectedConversationId)
//         .firstOrNull;
//   }

//   @override
//   Widget build(BuildContext context) {
//     final authUser = ref.watch(authControllerProvider).valueOrNull;
//     final authToken = ref.watch(authTokenProvider).valueOrNull;
//     final usersState = ref.watch(usersControllerProvider);
//     final chatState = ref.watch(chatOverviewControllerProvider);
//     // final connectionState = ref.watch(chatRealtimeControllerProvider);
//     final themeMode =
//         ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;

//     return Shortcuts(
//       shortcuts: const <ShortcutActivator, Intent>{
//         SingleActivator(LogicalKeyboardKey.keyF, control: true):
//             _SearchIntent(),
//         SingleActivator(LogicalKeyboardKey.keyN, control: true): _NewIntent(),
//         SingleActivator(LogicalKeyboardKey.escape): _EscIntent(),
//       },
//       child: Actions(
//         actions: <Type, Action<Intent>>{
//           _SearchIntent: CallbackAction<_SearchIntent>(
//             onInvoke: (_) {
//               if (_selectedConversationId != null && !_showAdminPanel) {
//                 setState(() {
//                   _searchSignal++;
//                 });
//               }
//               return null;
//             },
//           ),
//           _NewIntent: CallbackAction<_NewIntent>(
//             onInvoke: (_) async {
//               final data = ref.read(chatOverviewControllerProvider).valueOrNull;
//               final currentUser = ref.read(authControllerProvider).valueOrNull;
//               if (data != null && currentUser != null) {
//                 await _showCreateDialog(
//                   currentUser: currentUser,
//                   overview: data,
//                 );
//               }
//               return null;
//             },
//           ),
//           _EscIntent: CallbackAction<_EscIntent>(
//             onInvoke: (_) {
//               if (_showRightPanel) {
//                 setState(() => _showRightPanel = false);
//               }
//               return null;
//             },
//           ),
//         },
//         child: Focus(
//           autofocus: true,
//           child: Scaffold(
//             appBar: AppBar(),
//             body: SafeArea(
//               child: Padding(
//                 padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
//                 child: Column(
//                   children: [
//                     // ChatConnectionBanner(state: connectionState),
//                     Expanded(
//                       child: chatState.when(
//                         loading: () =>
//                             const Center(child: CircularProgressIndicator()),
//                         error: (error, _) =>
//                             Center(child: Text(error.toString())),
//                         data: (overview) {
//                           final allConversations = sortConversationsForSidebar(
//                             overview.conversations,
//                           );
//                           final visibleConversations = _visibleConversations(
//                             allConversations,
//                             authUser?.id ?? '',
//                           );
//                           _ensureSelection(
//                             allConversations: allConversations,
//                             visibleConversations: visibleConversations,
//                           );

//                           final selectedConversation = _selectedConversation(
//                             allConversations,
//                           );

//                           return _buildDesktopShell(
//                             authUser: authUser,
//                             authToken: authToken,
//                             usersState: usersState,
//                             overview: overview,
//                             themeMode: themeMode,
//                             visibleConversations: visibleConversations,
//                             selectedConversation: selectedConversation,
//                           );
//                         },
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildDesktopShell({
//     required AppUser? authUser,
//     required String? authToken,
//     required AsyncValue<List<ManagedUser>> usersState,
//     required ChatOverviewData overview,
//     required ThemeMode themeMode,
//     required List<ChatConversation> visibleConversations,
//     required ChatConversation? selectedConversation,
//   }) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Theme.of(context).colorScheme.surface,
//         borderRadius: BorderRadius.circular(18),
//         border: Border.all(
//           color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
//         ),
//       ),
//       child: ClipRRect(
//         borderRadius: BorderRadius.circular(18),
//         child: Row(
//           children: [
//             SizedBox(
//               width: _sidebarWidth,
//               child: ChatSidebar(
//                 currentUser: authUser,
//                 currentThemeMode: themeMode,
//                 searchController: _sidebarSearchController,
//                 currentFilter: _sidebarFilter,
//                 conversations: visibleConversations,
//                 selectedConversationId: _selectedConversationId,
//                 onFilterChanged: (filter) {
//                   setState(() => _sidebarFilter = filter);
//                 },
//                 onConversationSelected: (conversation) {
//                   _selectConversation(conversation);
//                 },
//                 onCreateConversation: () async {
//                   if (authUser == null) {
//                     return;
//                   }
//                   await _showCreateDialog(
//                     currentUser: authUser,
//                     overview: overview,
//                   );
//                 },
//                 onRefresh: () {
//                   ref.read(chatOverviewControllerProvider.notifier).refresh();
//                 },
//                 onOpenAdmin: () {
//                   setState(() {
//                     _showAdminPanel = true;
//                     _showRightPanel = false;
//                   });
//                   _setActiveConversation(null);
//                 },
//                 onToggleTheme: () {
//                   ref
//                       .read(themeModeControllerProvider.notifier)
//                       .cycleThemeMode();
//                 },
//                 onTogglePin: (conversation) {
//                   _updateConversationPreferences(
//                     conversation,
//                     isPinned: !conversation.isPinned,
//                   );
//                 },
//                 onToggleMute: (conversation) {
//                   _updateConversationPreferences(
//                     conversation,
//                     isMuted: !conversation.isMuted,
//                   );
//                 },
//                 onToggleArchive: (conversation) {
//                   _updateConversationPreferences(
//                     conversation,
//                     isArchived: !conversation.isArchived,
//                   );
//                 },
//                 onDeleteConversation: (conversation) {
//                   _deleteConversation(conversation);
//                 },
//               ),
//             ),
//             _ResizeHandle(
//               onDrag: (delta) {
//                 setState(() {
//                   _sidebarWidth = (_sidebarWidth + delta.delta.dx).clamp(
//                     250,
//                     420,
//                   );
//                 });
//               },
//             ),
//             Expanded(
//               child: Container(
//                 color: Theme.of(context).colorScheme.surfaceContainer,
//                 child: _showAdminPanel
//                     ? ChatAdminPanel(
//                         departments: overview.departments,
//                         manageableConversations:
//                             overview.manageableConversations,
//                         users: overview.users,
//                         roles: overview.roles,
//                         usersState: usersState,
//                       )
//                     : selectedConversation == null
//                     ? const _EmptyConversationState()
//                     : ChatScreen(
//                         key: ValueKey('chat_${selectedConversation.id}'),
//                         conversation: selectedConversation,
//                         currentUser: authUser,
//                         token: authToken,
//                         searchSignal: _searchSignal,
//                         rightPanelVisible: _showRightPanel,
//                         onToggleRightPanel: () {
//                           setState(() => _showRightPanel = !_showRightPanel);
//                         },
//                         onConversationDeleted: () {
//                           if (_selectedConversationId ==
//                               selectedConversation.id) {
//                             _selectConversation(null);
//                           }
//                         },
//                       ),
//               ),
//             ),
//             AnimatedSwitcher(
//               duration: const Duration(milliseconds: 220),
//               transitionBuilder: (child, animation) {
//                 return SizeTransition(
//                   axis: Axis.horizontal,
//                   sizeFactor: animation,
//                   axisAlignment: -1,
//                   child: child,
//                 );
//               },
//               child:
//                   !_showAdminPanel &&
//                       _showRightPanel &&
//                       selectedConversation != null
//                   ? Row(
//                       key: ValueKey('right_${selectedConversation.id}'),
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         _ResizeHandle(
//                           onDrag: (delta) {
//                             setState(() {
//                               _rightPanelWidth =
//                                   (_rightPanelWidth - delta.delta.dx).clamp(
//                                     280,
//                                     480,
//                                   );
//                             });
//                           },
//                         ),
//                         SizedBox(
//                           width: _rightPanelWidth,
//                           child: RightPanel(
//                             conversation: selectedConversation,
//                             currentUser: authUser,
//                             onClose: () {
//                               setState(() => _showRightPanel = false);
//                             },
//                             onTogglePinned: () {
//                               _updateConversationPreferences(
//                                 selectedConversation,
//                                 isPinned: !selectedConversation.isPinned,
//                               );
//                             },
//                             onToggleMuted: () {
//                               _updateConversationPreferences(
//                                 selectedConversation,
//                                 isMuted: !selectedConversation.isMuted,
//                               );
//                             },
//                             onToggleArchived: () {
//                               _updateConversationPreferences(
//                                 selectedConversation,
//                                 isArchived: !selectedConversation.isArchived,
//                               );
//                             },
//                             onDeleteConversation: () {
//                               _deleteConversation(selectedConversation);
//                             },
//                             onOpenGroupManagement: () {
//                               _openGroupManagement(selectedConversation);
//                             },
//                           ),
//                         ),
//                       ],
//                     )
//                   : const SizedBox.shrink(key: ValueKey('right_closed')),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _ResizeHandle extends StatelessWidget {
//   const _ResizeHandle({required this.onDrag});

//   final ValueChanged<DragUpdateDetails> onDrag;

//   @override
//   Widget build(BuildContext context) {
//     return MouseRegion(
//       cursor: SystemMouseCursors.resizeColumn,
//       child: GestureDetector(
//         behavior: HitTestBehavior.translucent,
//         onHorizontalDragUpdate: onDrag,
//         child: Container(
//           width: 6,
//           color: Theme.of(context).colorScheme.surface,
//           child: Center(
//             child: Container(
//               width: 2,
//               height: 48,
//               decoration: BoxDecoration(
//                 color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
//                 borderRadius: BorderRadius.circular(999),
//               ),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _EmptyConversationState extends StatelessWidget {
//   const _EmptyConversationState();

//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(28),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Container(
//               width: 92,
//               height: 92,
//               decoration: BoxDecoration(
//                 color: const Color(0xFFE7F0FA),
//                 borderRadius: BorderRadius.circular(26),
//               ),
//               child: const Icon(
//                 Icons.chat_bubble_rounded,
//                 size: 40,
//                 color: Color(0xFF3390EC),
//               ),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               'Select a conversation',
//               style: Theme.of(
//                 context,
//               ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Use Ctrl + N for a new chat, Ctrl + F to search in current chat.',
//               textAlign: TextAlign.center,
//               style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                 color: Theme.of(context).colorScheme.onSurfaceVariant,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _SearchIntent extends Intent {
//   const _SearchIntent();
// }

// class _NewIntent extends Intent {
//   const _NewIntent();
// }

// class _EscIntent extends Intent {
//   const _EscIntent();
// }

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
import 'widgets/chat_screen.dart';
import 'widgets/chat_sidebar.dart';
import 'widgets/chat_ui_helpers.dart';
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
  TicketTypeTab _activeTicketTab = TicketTypeTab.ticket;
  double _sidebarWidth = 300;
  double _rightPanelWidth = 320;
  int _searchSignal = 0;
  int _adminTabIndex = 0;
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
  }) {
    setState(() {
      _selectedConversationId = conversation?.id;
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
    final conversation = await Navigator.of(context).push<ChatConversation>(
      MaterialPageRoute(builder: (_) => const FavoriteMessagesScreen()),
    );
    if (!mounted || conversation == null) {
      return;
    }
    _selectConversation(conversation);
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
    final canDeleteForEveryone =
        authUser?.role == 'admin' || conversation.createdBy == authUser?.id;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('مسح المحادثة عندي'),
              subtitle: const Text('يتم حذف الرسائل عندك فقط'),
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
                subtitle: const Text('يحذف المحادثة بالكامل من كل الأطراف'),
                onTap: () => Navigator.of(context).pop('global'),
              ),
          ],
        ),
      ),
    );

    if (action == null) {
      return;
    }

    try {
      if (action == 'leave') {
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .leaveConversation(conversation.id);
        if (!mounted) return;
        if (_selectedConversationId == conversation.id) {
          _selectConversation(null);
        }
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
      } else {
        await ref
            .read(chatOverviewControllerProvider.notifier)
            .deleteConversation(conversation.id);
      }

      if (!mounted) return;
      if (_selectedConversationId == conversation.id) {
        _selectConversation(null);
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
              child: chatState.when(
                loading: () => const Center(
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
                ),
                error: (error, _) => Center(child: Text(error.toString())),
                data: (overview) {
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
                },
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
                    await ref
                        .read(chatOverviewControllerProvider.notifier)
                        .refresh();
                    await ref.read(chatFoldersProvider.notifier).refresh();
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
                  onToggleMute: (c) =>
                      _updateConversationPreferences(c, isMuted: !c.isMuted),
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
                            setState(() => _activeTicketTab = tab);
                          },
                        ),
                        const Divider(height: 1),
                      ],
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
                            initialTab: _activeTicketTab,
                            onTabChanged: (tab) {
                              setState(() => _activeTicketTab = tab);
                            },
                          )
                        : selectedConversation == null
                        ? const _TelegramEmptyState()
                        : ChatScreen(
                            key: ValueKey('chat_${selectedConversation.id}'),
                            conversation: selectedConversation,
                            currentUser: authUser,
                            token: authToken,
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
                                    isMuted: !selectedConversation.isMuted,
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
