// import 'dart:async';

// import 'package:desktop_drop/desktop_drop.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:intl/intl.dart';
// import 'package:open_filex/open_filex.dart';

// import '../../../shared/providers/providers.dart';
// import '../data/chat_socket_service.dart';
// import '../models/chat_models.dart';
// import 'group_management_dialog.dart';

// class ConversationPanel extends ConsumerStatefulWidget {
//   const ConversationPanel({
//     super.key,
//     required this.conversation,
//     this.onConversationChanged,
//     this.onConversationDeleted,
//   });

//   final ChatConversation conversation;
//   final ValueChanged<ChatConversation>? onConversationChanged;
//   final VoidCallback? onConversationDeleted;

//   @override
//   ConsumerState<ConversationPanel> createState() => _ConversationPanelState();
// }

// class _ConversationPanelState extends ConsumerState<ConversationPanel> {
//   final _messageController = TextEditingController();
//   final _scrollController = ScrollController();
//   final _typingUsers = <String>{};
//   StreamSubscription<ChatSocketEvent>? _subscription;
//   Object? _typingDebounce;
//   ChatConversation? _conversation;
//   ChatMessage? _replyingTo;
//   ChatMessage? _editingMessage;
//   bool _draggingFiles = false;
//   int _lastMessageCount = 0;
//   late final ProviderContainer _container;

//   ChatConversation get _data => _conversation ?? widget.conversation;

//   @override
//   void initState() {
//     super.initState();
//     _container = ProviderScope.containerOf(context, listen: false);
//     _conversation = widget.conversation;
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _container.read(activeConversationIdProvider.notifier).state = _data.id;
//       _container.read(chatSocketServiceProvider).markActivity();
//     });
//     _scrollController.addListener(() {
//       if (_scrollController.hasClients &&
//           _scrollController.position.pixels <= 80) {
//         ref
//             .read(conversationMessagesControllerProvider(_data.id).notifier)
//             .loadMore();
//       }
//     });
//     _subscription = ref.read(chatSocketServiceProvider).events.listen((event) {
//       if (!mounted) return;
//       if (event.type == 'presence_updated' ||
//           event.type == 'user_online' ||
//           event.type == 'user_offline') {
//         final userId = event.payload['userId']?.toString();
//         if (userId == null || userId.isEmpty) {
//           return;
//         }
//         final members = _data.members
//             .map(
//               (member) => member.id == userId
//                   ? ChatDirectoryUser(
//                       id: member.id,
//                       username: member.username,
//                       fullName: member.fullName,
//                       role: member.role,
//                       departmentId: member.departmentId,
//                       isOnline:
//                           event.payload['isOnline'] as bool? ??
//                           event.type == 'user_online',
//                       presenceStatus:
//                           event.payload['presenceStatus']?.toString() ??
//                           ((event.payload['isOnline'] as bool? ??
//                                   event.type == 'user_online')
//                               ? 'online'
//                               : 'offline'),
//                       isActive: member.isActive,
//                       avatarUrl: member.avatarUrl,
//                       lastSeen: event.payload['lastSeen'] is String
//                           ? DateTime.tryParse(
//                               event.payload['lastSeen'] as String,
//                             )
//                           : member.lastSeen,
//                       lastActiveAt: event.payload['lastActiveAt'] is String
//                           ? DateTime.tryParse(
//                               event.payload['lastActiveAt'] as String,
//                             )
//                           : member.lastActiveAt,
//                     )
//                   : member,
//             )
//             .toList();
//         setState(() => _conversation = _data.copyWith(members: members));
//         return;
//       }
//       if (event.payload['conversationId'] != _data.id) return;
//       if (event.type == 'typing') {
//         final fullName = event.payload['fullName']?.toString();
//         if (fullName != null && fullName.isNotEmpty) {
//           setState(() => _typingUsers.add(fullName));
//         }
//       } else if (event.type == 'stop_typing') {
//         setState(() => _typingUsers.clear());
//       } else if (event.type == 'conversation_deleted') {
//         widget.onConversationDeleted?.call();
//       } else if (event.type == 'conversation_updated' &&
//           event.payload['id']?.toString() == _data.id) {
//         final updated = ChatConversation.fromJson(event.payload);
//         setState(() => _conversation = updated);
//         widget.onConversationChanged?.call(updated);
//       }
//     });
//   }

//   @override
//   void didUpdateWidget(covariant ConversationPanel oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (oldWidget.conversation.id != widget.conversation.id ||
//         oldWidget.conversation.updatedAt != widget.conversation.updatedAt) {
//       _conversation = widget.conversation;
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!mounted) return;
//         _container.read(activeConversationIdProvider.notifier).state = _data.id;
//       });
//     }
//   }

//   @override
//   void dispose() {
//     Future<void>(
//       () => _container.read(activeConversationIdProvider.notifier).state = null,
//     );
//     _subscription?.cancel();
//     _typingDebounce?.cancel();
//     _messageController.dispose();
//     _scrollController.dispose();
//     super.dispose();
//   }

//   void _scheduleStopTyping() {
//     ref
//         .read(conversationMessagesControllerProvider(_data.id).notifier)
//         .sendTyping();
//     _typingDebounce?.cancel();
//     // legacy debounce callback
//       ref
//           .read(conversationMessagesControllerProvider(_data.id).notifier)
//           .stopTyping();
//     });
//   }

//   Future<void> _sendText() async {
//     final text = _messageController.text.trim();
//     if (text.isEmpty) return;
//     final notifier = ref.read(
//       conversationMessagesControllerProvider(_data.id).notifier,
//     );
//     if (_editingMessage != null) {
//       await notifier.editMessage(messageId: _editingMessage!.id, content: text);
//     } else {
//       await notifier.sendText(text, replyToMessageId: _replyingTo?.id);
//     }
//     _messageController.clear();
//     setState(() {
//       _replyingTo = null;
//       _editingMessage = null;
//     });
//   }

//   Future<void> _sendFile([String? filePath]) async {
//     var path = filePath;
//     if (path == null) {
//       final result = await FilePicker.platform.pickFiles();
//       path = result?.files.single.path;
//     }
//     if (path == null || path.isEmpty) return;
//     await ref
//         .read(conversationMessagesControllerProvider(_data.id).notifier)
//         .sendFile(path, replyToMessageId: _replyingTo?.id);
//     setState(() {
//       _replyingTo = null;
//       _editingMessage = null;
//     });
//   }

//   Future<void> _openAttachment(ChatMessage message) async {
//     final localPath = await ref
//         .read(chatRepositoryProvider)
//         .downloadAttachment(message);
//     await OpenFilex.open(localPath);
//   }

//   Future<void> _showActions(ChatMessage message) async {
//     final authUser = ref.read(authControllerProvider).valueOrNull;
//     final senderId = message.sender?.id ?? message.senderId;
//     final canDelete =
//         authUser?.id == senderId || authUser?.can('canDeleteMessages') == true;
//     await showModalBottomSheet<void>(
//       context: context,
//       showDragHandle: true,
//       builder: (context) => SafeArea(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
//               child: Wrap(
//                 spacing: 8,
//                 runSpacing: 8,
//                 children: ['👍', '❤️', '😂', '🔥', '👏']
//                     .map(
//                       (emoji) => ActionChip(
//                         label: Text(emoji),
//                         onPressed: () async {
//                           Navigator.pop(context);
//                           await ref
//                               .read(
//                                 conversationMessagesControllerProvider(
//                                   _data.id,
//                                 ).notifier,
//                               )
//                               .toggleReaction(
//                                 messageId: message.id,
//                                 emoji: emoji,
//                               );
//                         },
//                       ),
//                     )
//                     .toList(),
//               ),
//             ),
//             ListTile(
//               leading: const Icon(Icons.reply_outlined),
//               title: const Text('رد'),
//               onTap: () {
//                 Navigator.pop(context);
//                 setState(() {
//                   _replyingTo = message;
//                   _editingMessage = null;
//                 });
//               },
//             ),
//             if (authUser?.id == senderId &&
//                 !message.hasAttachment &&
//                 !message.isDeleted)
//               ListTile(
//                 leading: const Icon(Icons.edit_outlined),
//                 title: const Text('تعديل'),
//                 onTap: () {
//                   Navigator.pop(context);
//                   setState(() {
//                     _editingMessage = message;
//                     _replyingTo = null;
//                     _messageController.text = message.content;
//                   });
//                 },
//               ),
//             if (canDelete && !message.isDeleted)
//               ListTile(
//                 leading: const Icon(Icons.delete_outline),
//                 title: const Text('حذف'),
//                 onTap: () async {
//                   Navigator.pop(context);
//                   await ref
//                       .read(
//                         conversationMessagesControllerProvider(
//                           _data.id,
//                         ).notifier,
//                       )
//                       .deleteMessage(message.id);
//                 },
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   Future<void> _updatePreferences({
//     bool? isPinned,
//     bool? isMuted,
//     bool? isArchived,
//   }) async {
//     try {
//       final updated = await ref
//           .read(chatOverviewControllerProvider.notifier)
//           .updateConversationPreferences(
//             conversationId: _data.id,
//             isPinned: isPinned,
//             isMuted: isMuted,
//             isArchived: isArchived,
//           );
//       if (!mounted) return;
//       setState(() => _conversation = updated);
//       widget.onConversationChanged?.call(updated);
//     } catch (error) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(error.toString())));
//     }
//   }

//   Future<void> _deleteConversation() async {
//     final shouldDelete = await showDialog<bool>(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('حذف المحادثة'),
//         content: const Text('سيتم حذف المحادثة بالكامل. هل تريد المتابعة؟'),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(context).pop(false),
//             child: const Text('إلغاء'),
//           ),
//           FilledButton(
//             onPressed: () => Navigator.of(context).pop(true),
//             child: const Text('حذف'),
//           ),
//         ],
//       ),
//     );
//     if (shouldDelete != true || !mounted) return;

//     try {
//       await ref
//           .read(chatOverviewControllerProvider.notifier)
//           .deleteConversation(_data.id);
//       if (!mounted) return;
//       widget.onConversationDeleted?.call();
//     } catch (error) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(error.toString())));
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final authUser = ref.watch(authControllerProvider).valueOrNull;
//     final token = ref.watch(authTokenProvider).valueOrNull;
//     final messagesState = ref.watch(
//       conversationMessagesControllerProvider(_data.id),
//     );
//     final peer = _data.type == 'direct'
//         ? _data.members
//               .where((entry) => entry.id != authUser?.id)
//               .cast<ChatDirectoryUser?>()
//               .firstWhere((_) => true, orElse: () => null)
//         : null;

//     final statusText = _typingUsers.isNotEmpty
//         ? (_data.type == 'direct'
//               ? 'يكتب الآن'
//               : 'يكتب الآن: ${_typingUsers.join('، ')}')
//         : (peer == null ? 'محادثة داخلية' : _presenceLabel(peer));
//     final statusColor = _typingUsers.isNotEmpty
//         ? const Color(0xFF3390EC)
//         : (peer == null
//               ? Theme.of(context).colorScheme.onSurfaceVariant
//               : _presenceColor(peer.presenceStatus));

//     return DropTarget(
//       onDragEntered: (_) => setState(() => _draggingFiles = true),
//       onDragExited: (_) => setState(() => _draggingFiles = false),
//       onDragDone: (details) async {
//         setState(() => _draggingFiles = false);
//         for (final file in details.files) {
//           await _sendFile(file.path);
//         }
//       },
//       child: Stack(
//         children: [
//           Column(
//             children: [
//               Container(
//                 width: double.infinity,
//                 padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
//                 decoration: BoxDecoration(
//                   color: const Color(0xFFF8FAFD),
//                   border: Border(
//                     bottom: BorderSide(
//                       color: Theme.of(
//                         context,
//                       ).dividerColor.withValues(alpha: 0.22),
//                     ),
//                   ),
//                 ),
//                 child: Row(
//                   children: [
//                     CircleAvatar(
//                       radius: 24,
//                       backgroundColor: Theme.of(
//                         context,
//                       ).colorScheme.primary.withValues(alpha: 0.12),
//                       child: peer?.avatarUrl?.isNotEmpty == true
//                           ? ClipOval(
//                               child: Image.network(
//                                 peer!.avatarUrl!,
//                                 width: 48,
//                                 height: 48,
//                                 fit: BoxFit.cover,
//                                 headers: token == null || token.isEmpty
//                                     ? null
//                                     : {'Authorization': 'Bearer $token'},
//                                 errorBuilder: (_, __, ___) => Icon(
//                                   _data.type == 'group'
//                                       ? Icons.groups_outlined
//                                       : Icons.person_outline,
//                                   color: Theme.of(context).colorScheme.primary,
//                                 ),
//                               ),
//                             )
//                           : Icon(
//                               _data.type == 'group'
//                                   ? Icons.groups_outlined
//                                   : Icons.person_outline,
//                               color: Theme.of(context).colorScheme.primary,
//                             ),
//                     ),
//                     const SizedBox(width: 14),
//                     Expanded(
//                       child: Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             _data.displayTitle(authUser?.id ?? ''),
//                             style: Theme.of(context).textTheme.titleLarge
//                                 ?.copyWith(fontWeight: FontWeight.w800),
//                           ),
//                           const SizedBox(height: 4),
//                           Row(
//                             children: [
//                               Container(
//                                 height: 10,
//                                 width: 10,
//                                 decoration: BoxDecoration(
//                                   color: _typingUsers.isNotEmpty
//                                       ? const Color(0xFF3390EC)
//                                       : (peer == null
//                                             ? Theme.of(
//                                                 context,
//                                               ).colorScheme.primary
//                                             : _presenceColor(
//                                                 peer.presenceStatus,
//                                               )),
//                                   borderRadius: BorderRadius.circular(999),
//                                 ),
//                               ),
//                               const SizedBox(width: 7),
//                               Expanded(
//                                 child: Text(
//                                   statusText,
//                                   style: Theme.of(context).textTheme.bodySmall
//                                       ?.copyWith(
//                                         color: statusColor,
//                                         fontWeight: FontWeight.w700,
//                                       ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ],
//                       ),
//                     ),
//                     if (_data.type == 'group' &&
//                         _data.createdBy == authUser?.id)
//                       IconButton(
//                         onPressed: () async {
//                           final updated = await showDialog<ChatConversation>(
//                             context: context,
//                             builder: (_) =>
//                                 GroupManagementDialog(conversation: _data),
//                           );
//                           if (updated != null && mounted) {
//                             setState(() => _conversation = updated);
//                           }
//                         },
//                         icon: const Icon(Icons.group_outlined),
//                         tooltip: 'إدارة المجموعة',
//                       ),
//                     PopupMenuButton<String>(
//                       tooltip: 'خيارات المحادثة',
//                       onSelected: (value) async {
//                         switch (value) {
//                           case 'pin':
//                             await _updatePreferences(isPinned: !_data.isPinned);
//                             break;
//                           case 'mute':
//                             await _updatePreferences(isMuted: !_data.isMuted);
//                             break;
//                           case 'archive':
//                             await _updatePreferences(
//                               isArchived: !_data.isArchived,
//                             );
//                             break;
//                           case 'delete':
//                             await _deleteConversation();
//                             break;
//                         }
//                       },
//                       itemBuilder: (context) => [
//                         PopupMenuItem(
//                           value: 'pin',
//                           child: Text(
//                             _data.isPinned ? 'إزالة التثبيت' : 'تثبيت المحادثة',
//                           ),
//                         ),
//                         PopupMenuItem(
//                           value: 'mute',
//                           child: Text(
//                             _data.isMuted ? 'إلغاء الكتم' : 'كتم المحادثة',
//                           ),
//                         ),
//                         PopupMenuItem(
//                           value: 'archive',
//                           child: Text(
//                             _data.isArchived
//                                 ? 'إلغاء الأرشفة'
//                                 : 'أرشفة المحادثة',
//                           ),
//                         ),
//                         const PopupMenuDivider(),
//                         const PopupMenuItem(
//                           value: 'delete',
//                           child: Text('حذف المحادثة بالكامل'),
//                         ),
//                       ],
//                     ),
//                     if (_data.isPinned) const Chip(label: Text('مثبتة')),
//                     if (_data.isMuted) const SizedBox(width: 8),
//                     if (_data.isMuted) const Chip(label: Text('مكتومة')),
//                   ],
//                 ),
//               ),
//               Expanded(
//                 child: Container(
//                   decoration: const BoxDecoration(
//                     gradient: LinearGradient(
//                       begin: Alignment.topLeft,
//                       end: Alignment.bottomRight,
//                       colors: [Color(0xFFF7F9FC), Color(0xFFF2F6FA)],
//                     ),
//                   ),
//                   child: messagesState.when(
//                     loading: () =>
//                         const Center(child: CircularProgressIndicator()),
//                     error: (error, _) => Center(child: Text(error.toString())),
//                     data: (messagesData) {
//                       final messages = messagesData.messages;
//                       if (messages.length != _lastMessageCount) {
//                         _lastMessageCount = messages.length;
//                         WidgetsBinding.instance.addPostFrameCallback((_) {
//                           if (_scrollController.hasClients) {
//                             _scrollController.jumpTo(
//                               _scrollController.position.maxScrollExtent,
//                             );
//                           }
//                         });
//                       }
//                       if (messages.isEmpty) {
//                         return const Center(child: Text('لا توجد رسائل بعد'));
//                       }
//                       return ListView.builder(
//                         controller: _scrollController,
//                         padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
//                         itemCount:
//                             messages.length +
//                             (messagesData.isLoadingMore ? 1 : 0),
//                         itemBuilder: (context, index) {
//                           if (index >= messages.length) {
//                             return const Padding(
//                               padding: EdgeInsets.all(12),
//                               child: Center(child: CircularProgressIndicator()),
//                             );
//                           }
//                           final message = messages[index];
//                           final previous = index > 0
//                               ? messages[index - 1]
//                               : null;
//                           final showDate =
//                               previous == null ||
//                               previous.createdAt.day != message.createdAt.day ||
//                               previous.createdAt.month !=
//                                   message.createdAt.month ||
//                               previous.createdAt.year != message.createdAt.year;
//                           final senderId =
//                               message.sender?.id ?? message.senderId;

//                           final isMine =
//                               authUser?.id.toString() == senderId.toString();
//                           final reply = message.replyToMessageId == null
//                               ? null
//                               : messages
//                                     .where(
//                                       (entry) =>
//                                           entry.id == message.replyToMessageId,
//                                     )
//                                     .cast<ChatMessage?>()
//                                     .firstWhere(
//                                       (_) => true,
//                                       orElse: () => null,
//                                     );
//                           final status = authUser == null || !isMine
//                               ? null
//                               : _status(message, authUser.id);
//                           final textColor = const Color(0xFF0F172A);
//                           final mutedText = const Color(0xFF64748B);
//                           final bubbleColor = isMine
//                               ? const Color(0xFFE8F3FF)
//                               : Colors.white;
//                           final bubbleBorderColor = isMine
//                               ? const Color(0xFFCFE4FA)
//                               : const Color(0xFFE2E8F0);
//                           final replyColor = isMine
//                               ? const Color(0xFFDFF0FF)
//                               : const Color(0xFFF5F7FA);
//                           return Column(
//                             children: [
//                               if (showDate)
//                                 Padding(
//                                   padding: const EdgeInsets.only(bottom: 10),
//                                   child: Container(
//                                     padding: const EdgeInsets.symmetric(
//                                       horizontal: 12,
//                                       vertical: 6,
//                                     ),
//                                     decoration: BoxDecoration(
//                                       color: Theme.of(
//                                         context,
//                                       ).colorScheme.surfaceContainerHighest,
//                                       borderRadius: BorderRadius.circular(999),
//                                     ),
//                                     child: Text(
//                                       DateFormat(
//                                         'yyyy/MM/dd',
//                                       ).format(message.createdAt.toLocal()),
//                                     ),
//                                   ),
//                                 ),
//                               Align(
//                                 alignment: isMine
//                                     ? Alignment.centerRight
//                                     : Alignment.centerLeft,
//                                 child: GestureDetector(
//                                   onSecondaryTap: () => _showActions(message),
//                                   onLongPress: () => _showActions(message),
//                                   child: ConstrainedBox(
//                                     constraints: const BoxConstraints(
//                                       maxWidth: 520,
//                                     ),
//                                     child: Container(
//                                       margin: const EdgeInsets.only(bottom: 10),
//                                       padding: const EdgeInsets.symmetric(
//                                         horizontal: 14,
//                                         vertical: 10,
//                                       ),
//                                       decoration: BoxDecoration(
//                                         color: bubbleColor,
//                                         borderRadius: BorderRadius.only(
//                                           topLeft: const Radius.circular(22),
//                                           topRight: const Radius.circular(22),
//                                           bottomLeft: Radius.circular(
//                                             isMine ? 22 : 6,
//                                           ),
//                                           bottomRight: Radius.circular(
//                                             isMine ? 6 : 22,
//                                           ),
//                                         ),
//                                         border: Border.all(
//                                           color: bubbleBorderColor,
//                                         ),
//                                       ),
//                                       child: Column(
//                                         crossAxisAlignment:
//                                             CrossAxisAlignment.start,
//                                         children: [
//                                           if (!isMine && _data.type != 'direct')
//                                             Padding(
//                                               padding: const EdgeInsets.only(
//                                                 bottom: 6,
//                                               ),
//                                               child: Text(
//                                                 message.sender?.displayName ??
//                                                     'مستخدم',
//                                                 style: Theme.of(context)
//                                                     .textTheme
//                                                     .labelMedium
//                                                     ?.copyWith(
//                                                       fontWeight:
//                                                           FontWeight.w800,
//                                                       color: textColor,
//                                                     ),
//                                               ),
//                                             ),
//                                           if (reply != null)
//                                             Container(
//                                               width: double.infinity,
//                                               margin: const EdgeInsets.only(
//                                                 bottom: 8,
//                                               ),
//                                               padding: const EdgeInsets.all(10),
//                                               decoration: BoxDecoration(
//                                                 color: replyColor,
//                                                 borderRadius:
//                                                     BorderRadius.circular(14),
//                                               ),
//                                               child: Text(
//                                                 reply.content.isNotEmpty
//                                                     ? reply.content
//                                                     : (reply.fileName ??
//                                                           'ملف مرفق'),
//                                                 maxLines: 2,
//                                                 overflow: TextOverflow.ellipsis,
//                                                 style: TextStyle(
//                                                   color: mutedText,
//                                                 ),
//                                               ),
//                                             ),
//                                           AnimatedSwitcher(
//                                             duration: const Duration(
//                                               milliseconds: 240,
//                                             ),
//                                             switchInCurve: Curves.easeOutCubic,
//                                             switchOutCurve: Curves.easeInCubic,
//                                             transitionBuilder:
//                                                 (child, animation) {
//                                                   return FadeTransition(
//                                                     opacity: animation,
//                                                     child: SizeTransition(
//                                                       sizeFactor: animation,
//                                                       axisAlignment: -1,
//                                                       child: child,
//                                                     ),
//                                                   );
//                                                 },
//                                             child: message.isDeleted
//                                                 ? Container(
//                                                     key: ValueKey(
//                                                       'deleted_${message.id}',
//                                                     ),
//                                                     alignment:
//                                                         Alignment.centerLeft,
//                                                     child: Text(
//                                                       'تم حذف هذه الرسالة',
//                                                       style: TextStyle(
//                                                         color: mutedText,
//                                                         fontStyle:
//                                                             FontStyle.italic,
//                                                       ),
//                                                     ),
//                                                   )
//                                                 : Column(
//                                                     key: ValueKey(
//                                                       'content_${message.id}',
//                                                     ),
//                                                     crossAxisAlignment:
//                                                         CrossAxisAlignment
//                                                             .start,
//                                                     children: [
//                                                       if (message
//                                                           .content
//                                                           .isNotEmpty)
//                                                         Text(
//                                                           message.content,
//                                                           style: TextStyle(
//                                                             color: textColor,
//                                                             height: 1.45,
//                                                           ),
//                                                         ),
//                                                       if (message.hasAttachment)
//                                                         InkWell(
//                                                           onTap: () =>
//                                                               _openAttachment(
//                                                                 message,
//                                                               ),
//                                                           child: Container(
//                                                             width:
//                                                                 double.infinity,
//                                                             margin:
//                                                                 const EdgeInsets.only(
//                                                                   top: 10,
//                                                                 ),
//                                                             padding:
//                                                                 const EdgeInsets.all(
//                                                                   10,
//                                                                 ),
//                                                             decoration:
//                                                                 BoxDecoration(
//                                                                   color:
//                                                                       replyColor,
//                                                                   borderRadius:
//                                                                       BorderRadius.circular(
//                                                                         14,
//                                                                       ),
//                                                                 ),
//                                                             child: Row(
//                                                               children: [
//                                                                 Icon(
//                                                                   _attachmentIcon(
//                                                                     message
//                                                                         .messageType,
//                                                                   ),
//                                                                   color:
//                                                                       textColor,
//                                                                 ),
//                                                                 const SizedBox(
//                                                                   width: 8,
//                                                                 ),
//                                                                 Expanded(
//                                                                   child: Text(
//                                                                     message.fileName ??
//                                                                         'ملف مرفق',
//                                                                     maxLines: 1,
//                                                                     overflow:
//                                                                         TextOverflow
//                                                                             .ellipsis,
//                                                                     style: TextStyle(
//                                                                       color:
//                                                                           textColor,
//                                                                     ),
//                                                                   ),
//                                                                 ),
//                                                               ],
//                                                             ),
//                                                           ),
//                                                         ),
//                                                       _ReactionWrap(
//                                                         message: message,
//                                                         currentUserId:
//                                                             authUser?.id,
//                                                         isMine: isMine,
//                                                         onToggle: (emoji) => ref
//                                                             .read(
//                                                               conversationMessagesControllerProvider(
//                                                                 _data.id,
//                                                               ).notifier,
//                                                             )
//                                                             .toggleReaction(
//                                                               messageId:
//                                                                   message.id,
//                                                               emoji: emoji,
//                                                             ),
//                                                       ),
//                                                     ],
//                                                   ),
//                                           ),
//                                           const SizedBox(height: 8),
//                                           Row(
//                                             mainAxisSize: MainAxisSize.min,
//                                             children: [
//                                               Text(
//                                                 DateFormat('HH:mm').format(
//                                                   message.createdAt.toLocal(),
//                                                 ),
//                                                 style: TextStyle(
//                                                   color: mutedText,
//                                                   fontSize: 12,
//                                                 ),
//                                               ),
//                                               if (message.isEdited) ...[
//                                                 const SizedBox(width: 6),
//                                                 Text(
//                                                   'معدلة',
//                                                   style: TextStyle(
//                                                     color: mutedText,
//                                                     fontSize: 12,
//                                                   ),
//                                                 ),
//                                               ],
//                                               if (status != null) ...[
//                                                 const SizedBox(width: 6),
//                                                 Icon(
//                                                   status.icon,
//                                                   size: 16,
//                                                   color: status.color,
//                                                 ),
//                                               ],
//                                             ],
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           );
//                         },
//                       );
//                     },
//                   ),
//                 ),
//               ),
//               if (_replyingTo != null || _editingMessage != null)
//                 Container(
//                   width: double.infinity,
//                   margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 14,
//                     vertical: 12,
//                   ),
//                   decoration: BoxDecoration(
//                     color: Theme.of(
//                       context,
//                     ).colorScheme.surfaceContainerHighest,
//                     borderRadius: BorderRadius.circular(18),
//                   ),
//                   child: Row(
//                     children: [
//                       Expanded(
//                         child: Text(
//                           _editingMessage != null
//                               ? 'تعديل رسالة: ${_editingMessage!.content}'
//                               : 'رد على: ${_replyingTo!.content.isNotEmpty ? _replyingTo!.content : (_replyingTo!.fileName ?? 'ملف مرفق')}',
//                           maxLines: 2,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),
//                       IconButton(
//                         onPressed: () => setState(() {
//                           _replyingTo = null;
//                           _editingMessage = null;
//                         }),
//                         icon: const Icon(Icons.close),
//                       ),
//                     ],
//                   ),
//                 ),
//               Container(
//                 padding: const EdgeInsets.all(20),
//                 decoration: BoxDecoration(
//                   border: Border(
//                     top: BorderSide(
//                       color: Theme.of(
//                         context,
//                       ).dividerColor.withValues(alpha: 0.22),
//                     ),
//                   ),
//                 ),
//                 child: Row(
//                   children: [
//                     IconButton(
//                       onPressed: () => _sendFile(),
//                       icon: const Icon(Icons.attach_file),
//                     ),
//                     Expanded(
//                       child: TextField(
//                         controller: _messageController,
//                         minLines: 1,
//                         maxLines: 5,
//                         onChanged: (_) => _scheduleStopTyping(),
//                         decoration: InputDecoration(
//                           hintText: _editingMessage != null
//                               ? 'عدّل الرسالة...'
//                               : 'اكتب رسالة...',
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     FilledButton(
//                       onPressed: _sendText,
//                       child: Text(_editingMessage != null ? 'حفظ' : 'إرسال'),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//           if (_draggingFiles)
//             Positioned.fill(
//               child: IgnorePointer(
//                 child: Container(
//                   margin: const EdgeInsets.all(20),
//                   decoration: BoxDecoration(
//                     color: Theme.of(
//                       context,
//                     ).colorScheme.primary.withValues(alpha: 0.1),
//                     borderRadius: BorderRadius.circular(24),
//                     border: Border.all(
//                       color: Theme.of(context).colorScheme.primary,
//                       width: 2,
//                     ),
//                   ),
//                   child: const Center(
//                     child: Text(
//                       'أفلت الملفات هنا لإرسالها',
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
// }

// class _MessageStatus {
//   const _MessageStatus(this.icon, this.color);
//   final IconData icon;
//   final Color color;
// }

// class _ReactionWrap extends StatelessWidget {
//   const _ReactionWrap({
//     required this.message,
//     required this.currentUserId,
//     required this.isMine,
//     required this.onToggle,
//   });

//   final ChatMessage message;
//   final String? currentUserId;
//   final bool isMine;
//   final Future<void> Function(String emoji) onToggle;

//   @override
//   Widget build(BuildContext context) {
//     final reactions = _reactionEntries(message);
//     if (reactions.isEmpty) {
//       return const SizedBox.shrink();
//     }

//     return Padding(
//       padding: const EdgeInsets.only(top: 10),
//       child: Wrap(
//         spacing: 6,
//         runSpacing: 6,
//         children: reactions
//             .map(
//               (entry) => InkWell(
//                 borderRadius: BorderRadius.circular(999),
//                 onTap: () => onToggle(entry.key),
//                 child: Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 8,
//                     vertical: 5,
//                   ),
//                   decoration: BoxDecoration(
//                     color: _reactionHasUser(entry.value, currentUserId)
//                         ? (isMine
//                               ? Colors.white.withValues(alpha: 0.22)
//                               : const Color(0xFFDDEFE9))
//                         : (isMine
//                               ? Colors.white.withValues(alpha: 0.16)
//                               : const Color(0xFFF1F5F9)),
//                     borderRadius: BorderRadius.circular(999),
//                   ),
//                   child: Text('${entry.key} ${entry.value.length}'),
//                 ),
//               ),
//             )
//             .toList(),
//       ),
//     );
//   }
// }

// String _presenceLabel(ChatDirectoryUser user) {
//   if (user.presenceStatus == 'online') return 'متصل الآن';
//   if (user.presenceStatus == 'idle') {
//     final at = user.lastActiveAt ?? user.lastSeen;
//     return at == null
//         ? 'خامل'
//         : 'خامل منذ ${DateFormat('HH:mm').format(at.toLocal())}';
//   }
//   final lastSeen = user.lastSeen ?? user.lastActiveAt;
//   return lastSeen == null
//       ? 'غير متصل'
//       : 'آخر ظهور ${DateFormat('yyyy/MM/dd HH:mm').format(lastSeen.toLocal())}';
// }

// Color _presenceColor(String status) => switch (status) {
//   'online' => const Color(0xFF22C55E),
//   'idle' => const Color(0xFFF59E0B),
//   _ => const Color(0xFF94A3B8),
// };

// _MessageStatus _status(ChatMessage message, String currentUserId) {
//   if (message.seenBy.any((entry) => entry.userId != currentUserId)) {
//     return const _MessageStatus(Icons.done_all_rounded, Color(0xFF16A34A));
//   }
//   if (message.deliveredTo.any((entry) => entry.userId != currentUserId)) {
//     return const _MessageStatus(Icons.done_all_rounded, Color(0xFF94A3B8));
//   }
//   return const _MessageStatus(Icons.done_rounded, Color(0xFF94A3B8));
// }

// IconData _attachmentIcon(String type) => switch (type) {
//   'image' => Icons.image_outlined,
//   'pdf' => Icons.picture_as_pdf_outlined,
//   _ => Icons.attach_file,
// };

// List<MapEntry<String, List<String>>> _reactionEntries(ChatMessage message) {
//   final metadata = message.metadata;
//   if (metadata == null) {
//     return const [];
//   }

//   final rawReactions = metadata['reactions'];
//   if (rawReactions is! Map) {
//     return const [];
//   }

//   return rawReactions.entries
//       .where((entry) => entry.key != null && entry.value is List)
//       .map(
//         (entry) => MapEntry(
//           entry.key.toString(),
//           (entry.value as List<dynamic>)
//               .map((userId) => userId.toString())
//               .toList(),
//         ),
//       )
//       .where((entry) => entry.value.isNotEmpty)
//       .toList();
// }

// bool _reactionHasUser(List<String> userIds, String? currentUserId) {
//   if (currentUserId == null || currentUserId.isEmpty) {
//     return false;
//   }
//   return userIds.contains(currentUserId);
// }

// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:desktop_app/features/chat/models/chat_models.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:intl/intl.dart';

// // ── Telegram bubble colours ────────────────────────────────────────────────────
// class _TgBubble {
//   // Mine (outgoing) — Telegram green/blue tint
//   static const mineBg = Color(0xFFEFFDDD); // Telegram's classic green
//   static const mineBorder = Color(0xFFD4F0B8);
//   static const mineText = Color(0xFF0F1E08);
//   static const mineSubtext = Color(0xFF6A9E4A);

//   // Theirs (incoming)
//   static const theirsBg = Color(0xFFFFFFFF);
//   static const theirsBorder = Color(0xFFE8EAED);
//   static const theirsText = Color(0xFF1C2B3A);
//   static const theirsSubtext = Color(0xFF708499);

//   // Dark mine
//   static const mineBgDark = Color(0xFF2B5278);
//   static const mineBorderDark = Color(0xFF3A6A9A);
//   static const mineTextDark = Color(0xFFE8F5FF);
//   static const mineSubtextDark = Color(0xFF8BBBD8);

//   // Dark theirs
//   static const theirsBgDark = Color(0xFF212D3B);
//   static const theirsBorderDk = Color(0xFF2B3A4A);
//   static const theirsTextDark = Color(0xFFE8ECF0);
//   static const theirsSubtextDk = Color(0xFF708499);

//   // Reactions
//   static const reactBgMine = Color(0xFFD8F6B0);
//   static const reactBgTheirs = Color(0xFFF0F2F5);
//   static const reactBgMineDark = Color(0xFF1E3D5C);
//   static const reactBgTheirsDk = Color(0xFF2C3A48);
//   static const reactSelected = Color(0xFF3390EC);
// }

// // ─────────────────────────────────────────────────────────────────────────────

// class MessageBubble extends StatelessWidget {
//   const MessageBubble({
//     super.key,
//     required this.message,
//     required this.isMine,
//     required this.showAvatar,
//     required this.showSenderName,
//     required this.senderName,
//     required this.currentUserId,
//     required this.onReply,
//     required this.onCopy,
//     required this.onOpenAttachment,
//     required this.onReact,
//     this.avatarUrl,
//     this.token,
//     this.replyPreview,
//     this.highlightQuery,
//     this.onEdit,
//     this.onDelete,
//   });

//   final ChatMessage message;
//   final bool isMine;
//   final bool showAvatar;
//   final bool showSenderName;
//   final String senderName;
//   final String currentUserId;
//   final String? avatarUrl;
//   final String? token;
//   final String? replyPreview;
//   final String? highlightQuery;
//   final VoidCallback onReply;
//   final VoidCallback onCopy;
//   final VoidCallback? onEdit;
//   final VoidCallback? onDelete;
//   final VoidCallback onOpenAttachment;
//   final Future<void> Function(String emoji) onReact;

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;

//     return Align(
//       // ── رسائلي يمين، رسائل الآخرين يسار ──────────────────────────────────
//       alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.end,
//         // isMine → avatar على اليمين بعد الفقاعة، لكن Telegram لا يظهر avatar للمرسل
//         // نعكس الترتيب للرسائل الواردة فقط
//         children: isMine
//             ? [
//                 _BubbleBody(
//                   message: message,
//                   isMine: isMine,
//                   isDark: isDark,
//                   showSenderName: showSenderName,
//                   senderName: senderName,
//                   currentUserId: currentUserId,
//                   replyPreview: replyPreview,
//                   highlightQuery: highlightQuery,
//                   onReply: onReply,
//                   onCopy: onCopy,
//                   onEdit: onEdit,
//                   onDelete: onDelete,
//                   onOpenAttachment: onOpenAttachment,
//                   onReact: onReact,
//                 ),
//               ]
//             : [
//                 // Avatar للرسائل الواردة
//                 if (showAvatar)
//                   _SenderAvatar(
//                     avatarUrl: avatarUrl,
//                     senderName: senderName,
//                     token: token,
//                     isDark: isDark,
//                   )
//                 else
//                   const SizedBox(width: 36),
//                 const SizedBox(width: 6),
//                 _BubbleBody(
//                   message: message,
//                   isMine: isMine,
//                   isDark: isDark,
//                   showSenderName: showSenderName,
//                   senderName: senderName,
//                   currentUserId: currentUserId,
//                   replyPreview: replyPreview,
//                   highlightQuery: highlightQuery,
//                   onReply: onReply,
//                   onCopy: onCopy,
//                   onEdit: onEdit,
//                   onDelete: onDelete,
//                   onOpenAttachment: onOpenAttachment,
//                   onReact: onReact,
//                 ),
//               ],
//       ),
//     );
//   }
// }

// // ── Sender avatar ──────────────────────────────────────────────────────────────
// class _SenderAvatar extends StatelessWidget {
//   const _SenderAvatar({
//     required this.senderName,
//     required this.isDark,
//     this.avatarUrl,
//     this.token,
//   });

//   final String senderName;
//   final bool isDark;
//   final String? avatarUrl;
//   final String? token;

//   @override
//   Widget build(BuildContext context) {
//     return CircleAvatar(
//       radius: 16,
//       backgroundColor: const Color(0xFF3390EC).withValues(alpha: 0.2),
//       backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
//           ? CachedNetworkImageProvider(
//               avatarUrl!,
//               headers: token != null && token!.isNotEmpty
//                   ? {'Authorization': 'Bearer $token'}
//                   : null,
//             )
//           : null,
//       child: avatarUrl != null && avatarUrl!.isNotEmpty
//           ? null
//           : Text(
//               _firstChar(senderName),
//               style: const TextStyle(
//                 fontSize: 12,
//                 fontWeight: FontWeight.w700,
//                 color: Color(0xFF3390EC),
//               ),
//             ),
//     );
//   }
// }

// // ── Bubble body ────────────────────────────────────────────────────────────────
// class _BubbleBody extends StatefulWidget {
//   const _BubbleBody({
//     required this.message,
//     required this.isMine,
//     required this.isDark,
//     required this.showSenderName,
//     required this.senderName,
//     required this.currentUserId,
//     required this.onReply,
//     required this.onCopy,
//     required this.onOpenAttachment,
//     required this.onReact,
//     this.replyPreview,
//     this.highlightQuery,
//     this.onEdit,
//     this.onDelete,
//   });

//   final ChatMessage message;
//   final bool isMine;
//   final bool isDark;
//   final bool showSenderName;
//   final String senderName;
//   final String currentUserId;
//   final String? replyPreview;
//   final String? highlightQuery;
//   final VoidCallback onReply;
//   final VoidCallback onCopy;
//   final VoidCallback? onEdit;
//   final VoidCallback? onDelete;
//   final VoidCallback onOpenAttachment;
//   final Future<void> Function(String emoji) onReact;

//   @override
//   State<_BubbleBody> createState() => _BubbleBodyState();
// }

// class _BubbleBodyState extends State<_BubbleBody> {
//   bool _hovered = false;
//   bool _showEmoji = false;

//   // Telegram emoji picker
//   static const _quickEmojis = ['👍', '❤️', '😂', '🔥', '👏', '😮'];

//   Color get _bubbleBg {
//     if (widget.isMine) {
//       return widget.isDark ? _TgBubble.mineBgDark : _TgBubble.mineBg;
//     }
//     return widget.isDark ? _TgBubble.theirsBgDark : _TgBubble.theirsBg;
//   }

//   Color get _bubbleBorder {
//     if (widget.isMine) {
//       return widget.isDark ? _TgBubble.mineBorderDark : _TgBubble.mineBorder;
//     }
//     return widget.isDark ? _TgBubble.theirsBorderDk : _TgBubble.theirsBorder;
//   }

//   Color get _textColor {
//     if (widget.isMine) {
//       return widget.isDark ? _TgBubble.mineTextDark : _TgBubble.mineText;
//     }
//     return widget.isDark ? _TgBubble.theirsTextDark : _TgBubble.theirsText;
//   }

//   Color get _subtextColor {
//     if (widget.isMine) {
//       return widget.isDark ? _TgBubble.mineSubtextDark : _TgBubble.mineSubtext;
//     }
//     return widget.isDark ? _TgBubble.theirsSubtextDk : _TgBubble.theirsSubtext;
//   }

//   Color get _replyBg {
//     if (widget.isMine) {
//       return widget.isDark ? const Color(0xFF1E3D5C) : const Color(0xFFDCF8B0);
//     }
//     return widget.isDark ? const Color(0xFF1A2632) : const Color(0xFFF5F7FA);
//   }

//   // Telegram bubble tail shape
//   BorderRadius get _radius {
//     const r = Radius.circular(18);
//     const rSmall = Radius.circular(4);
//     if (widget.isMine) {
//       return const BorderRadius.only(
//         topLeft: r,
//         topRight: r,
//         bottomLeft: r,
//         bottomRight: rSmall,
//       );
//     }
//     return const BorderRadius.only(
//       topLeft: r,
//       topRight: r,
//       bottomLeft: rSmall,
//       bottomRight: r,
//     );
//   }

//   void _toggleEmoji() => setState(() => _showEmoji = !_showEmoji);

//   @override
//   Widget build(BuildContext context) {
//     return ConstrainedBox(
//       constraints: BoxConstraints(
//         maxWidth: MediaQuery.of(context).size.width * 0.62,
//       ),
//       child: Column(
//         crossAxisAlignment: widget.isMine
//             ? CrossAxisAlignment.end
//             : CrossAxisAlignment.start,
//         children: [
//           // ── Hover action buttons (مثل Telegram) ───────────────────────────
//           if (_hovered)
//             _HoverActions(
//               isMine: widget.isMine,
//               isDark: widget.isDark,
//               showEmoji: _showEmoji,
//               quickEmojis: _quickEmojis,
//               onToggleEmoji: _toggleEmoji,
//               onReply: widget.onReply,
//               onCopy: widget.onCopy,
//               onEdit: widget.onEdit,
//               onDelete: widget.onDelete,
//               onReact: widget.onReact,
//             ),

//           // ── Bubble ────────────────────────────────────────────────────────
//           MouseRegion(
//             onEnter: (_) => setState(() => _hovered = true),
//             onExit: (_) => setState(() {
//               _hovered = false;
//               _showEmoji = false;
//             }),
//             child: GestureDetector(
//               onSecondaryTap: _showContextMenu,
//               onLongPress: _showContextMenu,
//               child: AnimatedContainer(
//                 duration: const Duration(milliseconds: 120),
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 12,
//                   vertical: 8,
//                 ),
//                 decoration: BoxDecoration(
//                   color: _bubbleBg,
//                   borderRadius: _radius,
//                   border: Border.all(color: _bubbleBorder, width: 1),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withValues(
//                         alpha: widget.isDark ? 0.2 : 0.06,
//                       ),
//                       blurRadius: 4,
//                       offset: const Offset(0, 1),
//                     ),
//                   ],
//                 ),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     // Sender name (group)
//                     if (widget.showSenderName)
//                       Padding(
//                         padding: const EdgeInsets.only(bottom: 4),
//                         child: Text(
//                           widget.senderName,
//                           style: TextStyle(
//                             fontSize: 12,
//                             fontWeight: FontWeight.w700,
//                             color: _senderNameColor(widget.senderName),
//                           ),
//                         ),
//                       ),

//                     // Reply preview
//                     if (widget.replyPreview != null)
//                       _ReplyPreview(
//                         text: widget.replyPreview!,
//                         bg: _replyBg,
//                         textColor: _subtextColor,
//                         isMine: widget.isMine,
//                       ),

//                     // Content
//                     AnimatedSwitcher(
//                       duration: const Duration(milliseconds: 240),
//                       switchInCurve: Curves.easeOutCubic,
//                       transitionBuilder: (child, anim) => FadeTransition(
//                         opacity: anim,
//                         child: SizeTransition(
//                           sizeFactor: anim,
//                           alignment: Alignment.topCenter,
//                           child: child,
//                         ),
//                       ),
//                       child: widget.message.isDeleted
//                           ? Padding(
//                               key: ValueKey('del_${widget.message.id}'),
//                               padding: const EdgeInsets.symmetric(vertical: 2),
//                               child: Row(
//                                 mainAxisSize: MainAxisSize.min,
//                                 children: [
//                                   Icon(
//                                     Icons.block_rounded,
//                                     size: 14,
//                                     color: _subtextColor,
//                                   ),
//                                   const SizedBox(width: 4),
//                                   Text(
//                                     'تم حذف هذه الرسالة',
//                                     style: TextStyle(
//                                       color: _subtextColor,
//                                       fontStyle: FontStyle.italic,
//                                       fontSize: 13,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             )
//                           : Column(
//                               key: ValueKey('cnt_${widget.message.id}'),
//                               crossAxisAlignment: CrossAxisAlignment.start,
//                               mainAxisSize: MainAxisSize.min,
//                               children: [
//                                 // Text
//                                 if (widget.message.content.isNotEmpty)
//                                   _HighlightedText(
//                                     text: widget.message.content,
//                                     query: widget.highlightQuery,
//                                     style: TextStyle(
//                                       color: _textColor,
//                                       fontSize: 14,
//                                       height: 1.45,
//                                     ),
//                                   ),

//                                 // Attachment
//                                 if (widget.message.hasAttachment)
//                                   _AttachmentTile(
//                                     message: widget.message,
//                                     bg: _replyBg,
//                                     textColor: _textColor,
//                                     onTap: widget.onOpenAttachment,
//                                   ),
//                               ],
//                             ),
//                     ),

//                     // ── Reactions ─────────────────────────────────────────
//                     _TelegramReactions(
//                       message: widget.message,
//                       currentUserId: widget.currentUserId,
//                       isMine: widget.isMine,
//                       isDark: widget.isDark,
//                       onToggle: widget.onReact,
//                     ),

//                     // ── Timestamp + status ────────────────────────────────
//                     const SizedBox(height: 4),
//                     Row(
//                       mainAxisSize: MainAxisSize.min,
//                       mainAxisAlignment: widget.isMine
//                           ? MainAxisAlignment.end
//                           : MainAxisAlignment.start,
//                       children: [
//                         if (widget.message.isEdited) ...[
//                           Text(
//                             'معدّلة',
//                             style: TextStyle(
//                               fontSize: 11,
//                               color: _subtextColor,
//                             ),
//                           ),
//                           const SizedBox(width: 4),
//                         ],
//                         Text(
//                           DateFormat(
//                             'HH:mm',
//                           ).format(widget.message.createdAt.toLocal()),
//                           style: TextStyle(fontSize: 11, color: _subtextColor),
//                         ),
//                         if (widget.isMine) ...[
//                           const SizedBox(width: 4),
//                           _MessageTick(
//                             message: widget.message,
//                             currentUserId: widget.currentUserId,
//                           ),
//                         ],
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   // Context menu on right-click / long press
//   void _showContextMenu() {
//     showModalBottomSheet<void>(
//       context: context,
//       showDragHandle: true,
//       backgroundColor: widget.isDark ? const Color(0xFF212121) : Colors.white,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       builder: (ctx) => SafeArea(
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             // Quick emoji row
//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                 children: _quickEmojis
//                     .map(
//                       (e) => _EmojiButton(
//                         emoji: e,
//                         isDark: widget.isDark,
//                         onTap: () async {
//                           Navigator.pop(ctx);
//                           await widget.onReact(e);
//                         },
//                       ),
//                     )
//                     .toList(),
//               ),
//             ),
//             const Divider(height: 1),
//             _CtxItem(
//               icon: Icons.reply_rounded,
//               label: 'رد',
//               isDark: widget.isDark,
//               onTap: () {
//                 Navigator.pop(ctx);
//                 widget.onReply();
//               },
//             ),
//             _CtxItem(
//               icon: Icons.copy_rounded,
//               label: 'نسخ',
//               isDark: widget.isDark,
//               onTap: () {
//                 Navigator.pop(ctx);
//                 Clipboard.setData(ClipboardData(text: widget.message.content));
//                 widget.onCopy();
//               },
//             ),
//             if (widget.onEdit != null)
//               _CtxItem(
//                 icon: Icons.edit_rounded,
//                 label: 'تعديل',
//                 isDark: widget.isDark,
//                 onTap: () {
//                   Navigator.pop(ctx);
//                   widget.onEdit!();
//                 },
//               ),
//             if (widget.onDelete != null)
//               _CtxItem(
//                 icon: Icons.delete_outline_rounded,
//                 label: 'حذف',
//                 isDark: widget.isDark,
//                 danger: true,
//                 onTap: () {
//                   Navigator.pop(ctx);
//                   widget.onDelete!();
//                 },
//               ),
//             const SizedBox(height: 8),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // ── Hover action bar (desktop) ─────────────────────────────────────────────────
// class _HoverActions extends StatelessWidget {
//   const _HoverActions({
//     required this.isMine,
//     required this.isDark,
//     required this.showEmoji,
//     required this.quickEmojis,
//     required this.onToggleEmoji,
//     required this.onReply,
//     required this.onCopy,
//     required this.onReact,
//     this.onEdit,
//     this.onDelete,
//   });

//   final bool isMine;
//   final bool isDark;
//   final bool showEmoji;
//   final List<String> quickEmojis;
//   final VoidCallback onToggleEmoji;
//   final VoidCallback onReply;
//   final VoidCallback onCopy;
//   final VoidCallback? onEdit;
//   final VoidCallback? onDelete;
//   final Future<void> Function(String) onReact;

//   @override
//   Widget build(BuildContext context) {
//     final bg = isDark ? const Color(0xFF2C3A48) : const Color(0xFFFFFFFF);
//     final shadow = BoxShadow(
//       color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
//       blurRadius: 8,
//       offset: const Offset(0, 2),
//     );

//     return Padding(
//       padding: const EdgeInsets.only(bottom: 4),
//       child: Column(
//         crossAxisAlignment: isMine
//             ? CrossAxisAlignment.end
//             : CrossAxisAlignment.start,
//         children: [
//           // ── Emoji picker popup ──────────────────────────────────────────
//           if (showEmoji)
//             Container(
//               margin: const EdgeInsets.only(bottom: 4),
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
//               decoration: BoxDecoration(
//                 color: bg,
//                 borderRadius: BorderRadius.circular(24),
//                 boxShadow: [shadow],
//               ),
//               child: Row(
//                 mainAxisSize: MainAxisSize.min,
//                 children: quickEmojis
//                     .map(
//                       (e) => _EmojiButton(
//                         emoji: e,
//                         isDark: isDark,
//                         onTap: () => onReact(e),
//                       ),
//                     )
//                     .toList(),
//               ),
//             ),

//           // ── Action icons ────────────────────────────────────────────────
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
//             decoration: BoxDecoration(
//               color: bg,
//               borderRadius: BorderRadius.circular(20),
//               boxShadow: [shadow],
//             ),
//             child: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 _HoverBtn(
//                   icon: Icons.add_reaction_outlined,
//                   tooltip: 'تفاعل',
//                   isDark: isDark,
//                   onTap: onToggleEmoji,
//                   active: showEmoji,
//                 ),
//                 _HoverBtn(
//                   icon: Icons.reply_rounded,
//                   tooltip: 'رد',
//                   isDark: isDark,
//                   onTap: onReply,
//                 ),
//                 _HoverBtn(
//                   icon: Icons.copy_rounded,
//                   tooltip: 'نسخ',
//                   isDark: isDark,
//                   onTap: onCopy,
//                 ),
//                 if (onEdit != null)
//                   _HoverBtn(
//                     icon: Icons.edit_rounded,
//                     tooltip: 'تعديل',
//                     isDark: isDark,
//                     onTap: onEdit!,
//                   ),
//                 if (onDelete != null)
//                   _HoverBtn(
//                     icon: Icons.delete_outline_rounded,
//                     tooltip: 'حذف',
//                     isDark: isDark,
//                     danger: true,
//                     onTap: onDelete!,
//                   ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _HoverBtn extends StatelessWidget {
//   const _HoverBtn({
//     required this.icon,
//     required this.isDark,
//     required this.onTap,
//     this.tooltip,
//     this.active = false,
//     this.danger = false,
//   });

//   final IconData icon;
//   final bool isDark;
//   final VoidCallback onTap;
//   final String? tooltip;
//   final bool active;
//   final bool danger;

//   @override
//   Widget build(BuildContext context) {
//     final color = danger
//         ? const Color(0xFFE53935)
//         : active
//         ? const Color(0xFF3390EC)
//         : (isDark ? Colors.white60 : const Color(0xFF708499));

//     return Tooltip(
//       message: tooltip ?? '',
//       child: InkWell(
//         borderRadius: BorderRadius.circular(16),
//         onTap: onTap,
//         child: Padding(
//           padding: const EdgeInsets.all(5),
//           child: Icon(icon, size: 17, color: color),
//         ),
//       ),
//     );
//   }
// }

// // ── Telegram-style animated reactions ─────────────────────────────────────────
// class _TelegramReactions extends StatelessWidget {
//   const _TelegramReactions({
//     required this.message,
//     required this.currentUserId,
//     required this.isMine,
//     required this.isDark,
//     required this.onToggle,
//   });

//   final ChatMessage message;
//   final String currentUserId;
//   final bool isMine;
//   final bool isDark;
//   final Future<void> Function(String) onToggle;

//   List<MapEntry<String, List<String>>> get _reactions {
//     final meta = message.metadata;
//     if (meta == null) return const [];
//     final raw = meta['reactions'];
//     if (raw is! Map) return const [];
//     return raw.entries
//         .where((e) => e.key != null && e.value is List)
//         .map(
//           (e) => MapEntry(
//             e.key.toString(),
//             (e.value as List).map((u) => u.toString()).toList(),
//           ),
//         )
//         .where((e) => e.value.isNotEmpty)
//         .toList();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final reactions = _reactions;
//     if (reactions.isEmpty) return const SizedBox.shrink();

//     return Padding(
//       padding: const EdgeInsets.only(top: 6),
//       child: Wrap(
//         spacing: 4,
//         runSpacing: 4,
//         children: reactions
//             .map(
//               (entry) => _AnimatedReactionChip(
//                 emoji: entry.key,
//                 count: entry.value.length,
//                 selected: entry.value.contains(currentUserId),
//                 isMine: isMine,
//                 isDark: isDark,
//                 onTap: () => onToggle(entry.key),
//               ),
//             )
//             .toList(),
//       ),
//     );
//   }
// }

// // ── Animated reaction chip (bounce مثل Telegram) ──────────────────────────────
// class _AnimatedReactionChip extends StatefulWidget {
//   const _AnimatedReactionChip({
//     required this.emoji,
//     required this.count,
//     required this.selected,
//     required this.isMine,
//     required this.isDark,
//     required this.onTap,
//   });

//   final String emoji;
//   final int count;
//   final bool selected;
//   final bool isMine;
//   final bool isDark;
//   final VoidCallback onTap;

//   @override
//   State<_AnimatedReactionChip> createState() => _AnimatedReactionChipState();
// }

// class _AnimatedReactionChipState extends State<_AnimatedReactionChip>
//     with SingleTickerProviderStateMixin {
//   late final AnimationController _ctrl;
//   late final Animation<double> _scale;

//   @override
//   void initState() {
//     super.initState();
//     _ctrl = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 320),
//     );
//     _scale = TweenSequence<double>([
//       TweenSequenceItem(
//         tween: Tween(
//           begin: 1.0,
//           end: 1.35,
//         ).chain(CurveTween(curve: Curves.easeOut)),
//         weight: 40,
//       ),
//       TweenSequenceItem(
//         tween: Tween(
//           begin: 1.35,
//           end: 0.88,
//         ).chain(CurveTween(curve: Curves.easeIn)),
//         weight: 30,
//       ),
//       TweenSequenceItem(
//         tween: Tween(
//           begin: 0.88,
//           end: 1.0,
//         ).chain(CurveTween(curve: Curves.elasticOut)),
//         weight: 30,
//       ),
//     ]).animate(_ctrl);
//   }

//   @override
//   void dispose() {
//     _ctrl.dispose();
//     super.dispose();
//   }

//   void _handleTap() {
//     _ctrl.forward(from: 0);
//     widget.onTap();
//   }

//   Color get _bg {
//     if (widget.selected) return _TgBubble.reactSelected.withValues(alpha: 0.18);
//     if (widget.isMine) {
//       return widget.isDark ? _TgBubble.reactBgMineDark : _TgBubble.reactBgMine;
//     }
//     return widget.isDark ? _TgBubble.reactBgTheirsDk : _TgBubble.reactBgTheirs;
//   }

//   Color get _border {
//     if (widget.selected) return _TgBubble.reactSelected;
//     return Colors.transparent;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: _handleTap,
//       child: ScaleTransition(
//         scale: _scale,
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 180),
//           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//           decoration: BoxDecoration(
//             color: _bg,
//             borderRadius: BorderRadius.circular(999),
//             border: Border.all(color: _border, width: 1.2),
//           ),
//           child: Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               Text(
//                 widget.emoji,
//                 style: const TextStyle(fontSize: 14, height: 1),
//               ),
//               const SizedBox(width: 4),
//               AnimatedSwitcher(
//                 duration: const Duration(milliseconds: 200),
//                 transitionBuilder: (child, anim) => ScaleTransition(
//                   scale: anim,
//                   child: FadeTransition(opacity: anim, child: child),
//                 ),
//                 child: Text(
//                   '${widget.count}',
//                   key: ValueKey(widget.count),
//                   style: TextStyle(
//                     fontSize: 12,
//                     fontWeight: FontWeight.w700,
//                     color: widget.selected
//                         ? _TgBubble.reactSelected
//                         : (widget.isDark
//                               ? Colors.white70
//                               : const Color(0xFF708499)),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// // ── Reply preview ──────────────────────────────────────────────────────────────
// class _ReplyPreview extends StatelessWidget {
//   const _ReplyPreview({
//     required this.text,
//     required this.bg,
//     required this.textColor,
//     required this.isMine,
//   });

//   final String text;
//   final Color bg;
//   final Color textColor;
//   final bool isMine;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: double.infinity,
//       margin: const EdgeInsets.only(bottom: 6),
//       padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
//       decoration: BoxDecoration(
//         color: bg,
//         borderRadius: BorderRadius.circular(10),
//         border: Border(
//           left: BorderSide(color: const Color(0xFF3390EC), width: 3),
//         ),
//       ),
//       child: Text(
//         text,
//         maxLines: 2,
//         overflow: TextOverflow.ellipsis,
//         style: TextStyle(fontSize: 12, color: textColor, height: 1.4),
//       ),
//     );
//   }
// }

// // ── Attachment tile ────────────────────────────────────────────────────────────
// class _AttachmentTile extends StatelessWidget {
//   const _AttachmentTile({
//     required this.message,
//     required this.bg,
//     required this.textColor,
//     required this.onTap,
//   });

//   final ChatMessage message;
//   final Color bg;
//   final Color textColor;
//   final VoidCallback onTap;

//   IconData get _icon => switch (message.messageType) {
//     'image' => Icons.image_outlined,
//     'pdf' => Icons.picture_as_pdf_outlined,
//     _ => Icons.attach_file_rounded,
//   };

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: onTap,
//       child: Container(
//         margin: const EdgeInsets.only(top: 6),
//         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//         decoration: BoxDecoration(
//           color: bg,
//           borderRadius: BorderRadius.circular(10),
//         ),
//         child: Row(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(_icon, size: 18, color: const Color(0xFF3390EC)),
//             const SizedBox(width: 6),
//             Flexible(
//               child: Text(
//                 message.fileName ?? 'مرفق',
//                 maxLines: 1,
//                 overflow: TextOverflow.ellipsis,
//                 style: TextStyle(
//                   fontSize: 13,
//                   color: textColor,
//                   decoration: TextDecoration.underline,
//                   decorationColor: const Color(0xFF3390EC),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // ── Highlighted text (search) ──────────────────────────────────────────────────
// class _HighlightedText extends StatelessWidget {
//   const _HighlightedText({required this.text, required this.style, this.query});

//   final String text;
//   final String? query;
//   final TextStyle style;

//   @override
//   Widget build(BuildContext context) {
//     if (query == null || query!.isEmpty) {
//       return Text(text, style: style);
//     }

//     final lower = text.toLowerCase();
//     final qLower = query!.toLowerCase();
//     final spans = <TextSpan>[];
//     int start = 0;

//     while (true) {
//       final idx = lower.indexOf(qLower, start);
//       if (idx == -1) {
//         spans.add(TextSpan(text: text.substring(start)));
//         break;
//       }
//       if (idx > start) {
//         spans.add(TextSpan(text: text.substring(start, idx)));
//       }
//       spans.add(
//         TextSpan(
//           text: text.substring(idx, idx + query!.length),
//           style: const TextStyle(
//             backgroundColor: Color(0xFFFFE066),
//             color: Colors.black,
//             fontWeight: FontWeight.w700,
//           ),
//         ),
//       );
//       start = idx + query!.length;
//     }

//     return RichText(
//       text: TextSpan(style: style, children: spans),
//     );
//   }
// }

// // ── Message tick ───────────────────────────────────────────────────────────────
// class _MessageTick extends StatelessWidget {
//   const _MessageTick({required this.message, required this.currentUserId});

//   final ChatMessage message;
//   final String currentUserId;

//   @override
//   Widget build(BuildContext context) {
//     final seenByOthers = message.seenBy.any((e) => e.userId != currentUserId);
//     final deliveredToOthers = message.deliveredTo.any(
//       (e) => e.userId != currentUserId,
//     );

//     if (seenByOthers) {
//       // Telegram blue double-tick for seen
//       return const Icon(
//         Icons.done_all_rounded,
//         size: 15,
//         color: Color(0xFF3390EC),
//       );
//     }
//     if (deliveredToOthers) {
//       // Grey double-tick for delivered
//       return Icon(
//         Icons.done_all_rounded,
//         size: 15,
//         color: const Color(0xFF708499).withValues(alpha: 0.7),
//       );
//     }
//     // Single tick for sent
//     return Icon(
//       Icons.done_rounded,
//       size: 15,
//       color: const Color(0xFF708499).withValues(alpha: 0.7),
//     );
//   }
// }

// // ── Emoji button ───────────────────────────────────────────────────────────────
// class _EmojiButton extends StatefulWidget {
//   const _EmojiButton({
//     required this.emoji,
//     required this.isDark,
//     required this.onTap,
//   });

//   final String emoji;
//   final bool isDark;
//   final VoidCallback onTap;

//   @override
//   State<_EmojiButton> createState() => _EmojiButtonState();
// }

// class _EmojiButtonState extends State<_EmojiButton>
//     with SingleTickerProviderStateMixin {
//   late final AnimationController _ctrl;
//   late final Animation<double> _scale;

//   @override
//   void initState() {
//     super.initState();
//     _ctrl = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 280),
//     );
//     _scale = TweenSequence<double>([
//       TweenSequenceItem(
//         tween: Tween(
//           begin: 1.0,
//           end: 1.4,
//         ).chain(CurveTween(curve: Curves.easeOut)),
//         weight: 50,
//       ),
//       TweenSequenceItem(
//         tween: Tween(
//           begin: 1.4,
//           end: 1.0,
//         ).chain(CurveTween(curve: Curves.elasticOut)),
//         weight: 50,
//       ),
//     ]).animate(_ctrl);
//   }

//   @override
//   void dispose() {
//     _ctrl.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: () {
//         _ctrl.forward(from: 0);
//         widget.onTap();
//       },
//       child: ScaleTransition(
//         scale: _scale,
//         child: Padding(
//           padding: const EdgeInsets.all(6),
//           child: Text(
//             widget.emoji,
//             style: const TextStyle(fontSize: 22, height: 1),
//           ),
//         ),
//       ),
//     );
//   }
// }

// // ── Context menu item ──────────────────────────────────────────────────────────
// class _CtxItem extends StatelessWidget {
//   const _CtxItem({
//     required this.icon,
//     required this.label,
//     required this.isDark,
//     required this.onTap,
//     this.danger = false,
//   });

//   final IconData icon;
//   final String label;
//   final bool isDark;
//   final VoidCallback onTap;
//   final bool danger;

//   @override
//   Widget build(BuildContext context) {
//     final color = danger
//         ? const Color(0xFFE53935)
//         : (isDark ? Colors.white : const Color(0xFF1C2B3A));

//     return ListTile(
//       dense: true,
//       leading: Icon(icon, color: color, size: 20),
//       title: Text(
//         label,
//         style: TextStyle(
//           fontSize: 14,
//           fontWeight: FontWeight.w500,
//           color: color,
//         ),
//       ),
//       onTap: onTap,
//     );
//   }
// }

// // ── Helpers ────────────────────────────────────────────────────────────────────
// String _firstChar(String v) {
//   final t = v.trim();
//   return t.isEmpty ? '؟' : t.substring(0, 1).toUpperCase();
// }

// // ألوان مميزة لأسماء المرسلين في المجموعات (مثل Telegram)
// Color _senderNameColor(String name) {
//   const colors = [
//     Color(0xFF3390EC),
//     Color(0xFF3DAD3D),
//     Color(0xFFE05C2D),
//     Color(0xFF9B59B6),
//     Color(0xFF1ABC9C),
//     Color(0xFFE74C3C),
//     Color(0xFF2980B9),
//     Color(0xFFF39C12),
//   ];
//   return colors[name.hashCode.abs() % colors.length];
// }
