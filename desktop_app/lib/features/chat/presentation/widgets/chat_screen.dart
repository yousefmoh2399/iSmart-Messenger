import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_app/features/chat/presentation/chat_appearance_screen.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:swipe_to/swipe_to.dart';

import '../../../../core/network/ip_address_utils.dart';
import '../../../../core/network/media_url_resolver.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/providers/providers.dart';
import '../../../../shared/services/web_platform_bridge.dart' as web_bridge;
import '../../../../shared/widgets/app_loading_placeholders.dart';
import '../../../../shared/widgets/button_loading_indicator.dart';
import '../../../../shared/widgets/safe_network_avatar.dart';
import '../../../../shared/widgets/shimmer_skeleton.dart';
import '../../../admin/models/update_management_models.dart';
import '../../data/chat_draft_store.dart';
import '../../data/chat_socket_service.dart';
import '../../models/chat_models.dart';
import '../../utils/chat_attachment_policy.dart';
import '../chat_appearance.dart';
import 'attachment_send_dialogs.dart';
import 'chat_forward_dialog.dart';
import 'broadcast_target_picker_dialog.dart';
import 'authenticated_attachment_image.dart';
import 'chat_animated_reaction_picker.dart';
import 'chat_input.dart';
import 'chat_ui_helpers.dart';
import 'gif_picker_panel.dart';
import 'message_bubble.dart';
import 'poll_creator_dialog.dart';
import 'scheduled_messages_list.dart';
import 'chat_remote_search_dialog.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    required this.conversation,
    required this.currentUser,
    required this.token,
    required this.searchSignal,
    required this.rightPanelVisible,
    required this.onToggleRightPanel,
    required this.onCloseConversation,
    required this.onConversationDeleted,
    this.initialTargetMessageId,
    super.key,
  });

  final ChatConversation conversation;
  final AppUser? currentUser;
  final String? token;
  final int searchSignal;
  final bool rightPanelVisible;
  final VoidCallback onToggleRightPanel;
  final VoidCallback onCloseConversation;
  final VoidCallback onConversationDeleted;
  final String? initialTargetMessageId;

  @override
  ConsumerState<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends ConsumerState<ChatScreen> {
  static const MethodChannel _windowChannel = MethodChannel('dbacd_hub/window');

  final TextEditingController _messageController = TextEditingController();
  static const _draftStore = ChatDraftStore();
  bool _restoringDraft = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _messageFocusNode = FocusNode();
  final Set<String> _typingUsers = <String>{};
  final Map<String, String> _typingUsersById = <String, String>{};
  final Map<String, Timer> _typingUserTimersById = <String, Timer>{};
  final Set<String> _selectedMessageIds = <String>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  String? _mentionQuery;
  List<ChatDirectoryUser> _mentionResults = [];
  late final ProviderContainer _container;

  ChatMessage? _replyingTo;
  bool _isSendingText = false;
  ChatMessage? _editingMessage;
  StreamSubscription<ChatSocketEvent>? _eventsSubscription;
  bool _draggingFiles = false;
  bool _showSearch = false;
  int _lastMessageCount = 0;
  int _activeSearchMatchIndex = 0;
  String? _focusedMessageId;
  Timer? _focusedMessageClearTimer;
  bool _isUploadingAttachment = false;
  double _uploadProgress = 0;
  String? _uploadingFileName;
  bool _isDownloadingAttachment = false;
  double _downloadProgress = 0;
  String? _downloadingFileName;
  bool _broadcastSendToAllDepartments = true;
  Set<String> _broadcastTargetDepartmentIds = <String>{};
  Set<String> _broadcastTargetUserIds = <String>{};
  bool _showScrollToBottomButton = false;
  int _unreadBelowCount = 0;
  String? _lastSeenMessageId;
  String? _lastLatestMessageId;
  BranchPeerDevice? _remotePeerDevice;
  bool _isResolvingRemotePeer = false;
  Timer? _stopTypingTimer;
  bool _isTyping = false;

  String get _conversationId => widget.conversation.id;

  static const int _chatMaxUploadBytesUser = 20 * 1024 * 1024;
  static const int _chatMaxUploadBytesAdmin = 200 * 1024 * 1024;

  int _maxChatAttachmentBytes() {
    final customLimitMB = widget.currentUser?.maxAttachmentSizeMB;
    final defaultLimit = widget.currentUser?.role == 'admin'
        ? _chatMaxUploadBytesAdmin
        : _chatMaxUploadBytesUser;

    if (customLimitMB != null) {
      final customBytes = customLimitMB * 1024 * 1024;
      return customBytes > defaultLimit ? customBytes : defaultLimit;
    }
    return defaultLimit;
  }

  void _showChatAttachmentSizeExceededSnackbar() {
    if (!mounted) {
      return;
    }
    final limitMB = _maxChatAttachmentBytes() ~/ (1024 * 1024);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('الحد الأقصى لحجم مرفقات الشات هو $limitMB ميجا فقط.'),
      ),
    );
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onMessageTextChanged);
    _messageController.addListener(_onMessageDraftChanged);
    _container = ProviderScope.containerOf(context, listen: false);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = _container.read(pendingChatDropFilesProvider);
      if (pending != null &&
          pending['files'] != null &&
          pending['conversationId'] == _conversationId) {
        final files = pending['files'] as List<dynamic>;
        _container.read(pendingChatDropFilesProvider.notifier).state = null;

        final overview = _container
            .read(chatOverviewControllerProvider)
            .valueOrNull;
        final liveConversation =
            overview?.conversations
                .where((c) => c.id == _conversationId)
                .firstOrNull ??
            widget.conversation;

        if (!_isReadOnlyConversation(liveConversation)) {
          for (final file in files) {
            if (kIsWeb) {
              file.readAsBytes().then((bytes) {
                _sendPickedWebFiles(
                  conversation: liveConversation,
                  files: [
                    PlatformFile(
                      name: file.name,
                      size: bytes.length,
                      bytes: bytes,
                    ),
                  ],
                  isImageBatch: false,
                );
              });
            } else {
              _sendFile(file.path);
            }
          }
        }
      }
    });
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _activeSearchMatchIndex = 0;
          _focusedMessageId = null;
        });
      }
    });
    _listenToSocket();
    unawaited(_refreshRemotePeerDevice());
    unawaited(_restoreDraft());
    if (widget.initialTargetMessageId != null) {
      _focusedMessageId = widget.initialTargetMessageId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(activeConversationIdProvider.notifier).state = _conversationId;
      final controller = ref.read(
        conversationMessagesControllerProvider(_conversationId).notifier,
      );
      controller.markSeen();
      controller.refresh();
      _messageFocusNode.requestFocus();
      if (widget.initialTargetMessageId != null) {
        _scrollToTargetWithRetry(widget.initialTargetMessageId!);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _typingUsers.clear();
      _typingUsersById.clear();
      _clearTypingUserTimers();
      _stopTypingTimer?.cancel();
      _stopTypingTimer = null;
      if (_isTyping) {
        _isTyping = false;
        ref
            .read(
              conversationMessagesControllerProvider(
                oldWidget.conversation.id,
              ).notifier,
            )
            .stopTyping();
      }
      _replyingTo = null;
      _editingMessage = null;
      _showSearch = false;
      _selectedMessageIds.clear();
      _searchController.clear();
      _messageController.clear();
      unawaited(_restoreDraft());
      _lastMessageCount = 0;
      _activeSearchMatchIndex = 0;
      _focusedMessageId = widget.initialTargetMessageId;
      _showScrollToBottomButton = false;
      _lastSeenMessageId = null;
      _lastLatestMessageId = null;
      _unreadBelowCount = 0;
      _messageKeys.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activeConversationIdProvider.notifier).state = _conversationId;
        final controller = ref.read(
          conversationMessagesControllerProvider(_conversationId).notifier,
        );
        controller.markSeen();
        controller.refresh();
        _messageFocusNode.requestFocus();
        if (widget.initialTargetMessageId != null) {
          _scrollToTargetWithRetry(widget.initialTargetMessageId!);
        }
      });
      unawaited(_refreshRemotePeerDevice());
    } else if (widget.initialTargetMessageId != null &&
        widget.initialTargetMessageId != oldWidget.initialTargetMessageId) {
      _focusedMessageId = widget.initialTargetMessageId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToTargetWithRetry(widget.initialTargetMessageId!);
      });
    }
    if (oldWidget.searchSignal != widget.searchSignal) {
      _openSearch();
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageTextChanged);
    _messageController.removeListener(_onMessageDraftChanged);
    final disposedConversationId = _conversationId;
    Future<void>(() {
      final activeConversation = _container.read(activeConversationIdProvider);
      if (activeConversation == disposedConversationId) {
        _container.read(activeConversationIdProvider.notifier).state = null;
      }
    });
    _eventsSubscription?.cancel();
    _stopTypingTimer?.cancel();
    _clearTypingUserTimers();
    if (_isTyping) {
      Future<void>(() {
        _container
            .read(
              conversationMessagesControllerProvider(
                disposedConversationId,
              ).notifier,
            )
            .stopTyping();
      });
    }
    _messageController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _messageFocusNode.dispose();
    _focusedMessageClearTimer?.cancel();
    _scrollController.dispose();
    _messageKeys.clear();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final targetConversationId = _conversationId;
    final draft = await _draftStore.load(targetConversationId);
    // After the async gap, verify widget is still mounted and still showing the same conversation
    if (!mounted || draft == null || draft.isEmpty) return;
    if (_conversationId != targetConversationId) return;
    _restoringDraft = true;
    _messageController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _restoringDraft = false;
  }

  void _onMessageDraftChanged() {
    if (_restoringDraft) return;
    unawaited(_draftStore.save(_conversationId, _messageController.text));
  }

  void _onMessageTextChanged() {
    if (widget.conversation.type != 'group' &&
        widget.conversation.type != 'department') {
      return;
    }
    final text = _messageController.text;
    final selection = _messageController.selection;
    if (selection.baseOffset >= 0 && selection.baseOffset <= text.length) {
      final textBeforeCursor = text.substring(0, selection.baseOffset);
      final match = RegExp(r'@(\S*)$').firstMatch(textBeforeCursor);
      if (match != null) {
        final query = match.group(1)!;
        _updateMentionQuery(query);
      } else {
        if (_mentionQuery != null) {
          setState(() => _mentionQuery = null);
        }
      }
    }
  }

  void _updateMentionQuery(String query) {
    final lowerQuery = query.toLowerCase();
    final allMembers = widget.conversation.members;
    final filtered = allMembers.where((m) {
      return m.displayName.toLowerCase().contains(lowerQuery) ||
          m.username.toLowerCase().contains(lowerQuery);
    }).toList();

    setState(() {
      _mentionQuery = query;
      _mentionResults = filtered;
    });
  }

  void _insertMention(ChatDirectoryUser user) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final textAfterCursor = text.substring(selection.baseOffset);

    final match = RegExp(r'@(\S*)$').firstMatch(textBeforeCursor);
    if (match != null) {
      final replaceStart = textBeforeCursor.lastIndexOf('@');
      final newTextBefore =
          text.substring(0, replaceStart) + '@${user.username} ';

      setState(() {
        _messageController.text = newTextBefore + textAfterCursor;
        _messageController.selection = TextSelection.collapsed(
          offset: newTextBefore.length,
        );
        _mentionQuery = null;
      });
    }
  }

  // ── Socket ─────────────────────────────────────────────────────────────────
  void _listenToSocket() {
    _eventsSubscription?.cancel();
    final socketService = ref.read(chatSocketServiceProvider);
    _eventsSubscription = socketService.events.listen((event) {
      if (!mounted) return;
      final conversationId = event.payload['conversationId']?.toString();

      if (event.type == 'conversation_deleted') {
        if (event.payload['conversationId']?.toString() == _conversationId) {
          widget.onConversationDeleted();
        }
        return;
      }
      if (conversationId != _conversationId) return;

      if (event.type == 'receive_message') {
        unawaited(_markSeenIfConversationIsVisible());
        return;
      }

      if (event.type == 'typing') {
        final userId = event.payload['userId']?.toString().trim();
        final fullName = event.payload['fullName']?.toString().trim();
        if (fullName != null && fullName.isNotEmpty) {
          setState(() {
            if (userId != null && userId.isNotEmpty) {
              _typingUsersById[userId] = fullName;
              _typingUsers
                ..clear()
                ..addAll(_typingUsersById.values);
              _scheduleTypingUserExpiry(userId);
            } else {
              _typingUsers.add(fullName);
            }
          });
        }
        return;
      }

      if (event.type == 'stop_typing') {
        final userId = event.payload['userId']?.toString().trim();
        final fullName = event.payload['fullName']?.toString().trim();
        setState(() {
          if (userId != null &&
              userId.isNotEmpty &&
              _typingUsersById.containsKey(userId)) {
            _typingUserTimersById.remove(userId)?.cancel();
            _typingUsersById.remove(userId);
            _typingUsers
              ..clear()
              ..addAll(_typingUsersById.values);
          } else if (fullName != null && fullName.isNotEmpty) {
            _typingUsers.remove(fullName);
            final removedIds = _typingUsersById.entries
                .where((entry) => entry.value == fullName)
                .map((entry) => entry.key)
                .toList();
            for (final removedId in removedIds) {
              _typingUserTimersById.remove(removedId)?.cancel();
            }
            _typingUsersById.removeWhere((_, name) => name == fullName);
          } else {
            _typingUsers.clear();
            _typingUsersById.clear();
            _clearTypingUserTimers();
          }
        });
      }
    });
  }

  void _scheduleTypingUserExpiry(String userId) {
    _typingUserTimersById[userId]?.cancel();
    _typingUserTimersById[userId] = Timer(const Duration(seconds: 4), () {
      _typingUserTimersById.remove(userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _typingUsersById.remove(userId);
        _typingUsers
          ..clear()
          ..addAll(_typingUsersById.values);
      });
    });
  }

  void _clearTypingUserTimers() {
    for (final timer in _typingUserTimersById.values) {
      timer.cancel();
    }
    _typingUserTimersById.clear();
  }

  ChatDirectoryUser? _directPeerFromConversation(
    ChatConversation conversation,
  ) {
    if (conversation.type != 'direct') {
      return null;
    }
    final currentUserId = widget.currentUser?.id ?? '';
    for (final member in conversation.members) {
      if (member.id != currentUserId) {
        return member;
      }
    }
    return null;
  }

  Future<BranchPeerDevice?> _refreshRemotePeerDevice() async {
    final peer = _directPeerFromConversation(widget.conversation);
    if (peer == null) {
      if (mounted) {
        setState(() => _remotePeerDevice = null);
      }
      return null;
    }
    if (mounted) {
      setState(() => _isResolvingRemotePeer = true);
    }
    try {
      var peers = await ref
          .read(updateManagementRepositoryProvider)
          .listBranchPeerDevices(
            userId: peer.id,
            includeSelf: true,
          );
      if (peers.isEmpty && peer.branchCode.trim().isNotEmpty) {
        peers = await ref
            .read(updateManagementRepositoryProvider)
            .listBranchPeerDevices(
              branchCode: peer.branchCode,
              userId: peer.id,
              includeSelf: true,
            );
      }
      final resolved = peers.isNotEmpty ? peers.first : null;
      if (mounted) {
        setState(() {
          _remotePeerDevice = resolved;
        });
      }
      return resolved;
    } catch (_) {
      if (mounted) {
        setState(() => _remotePeerDevice = null);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() => _isResolvingRemotePeer = false);
      }
    }
  }

  void _showChatSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _isConversationActuallyVisible() async {
    if (kIsWeb) {
      return web_bridge.isPageVisible();
    }
    try {
      final result = await _windowChannel.invokeMethod<dynamic>(
        'getWindowState',
      );
      if (result is Map) {
        final map = Map<Object?, Object?>.from(result);
        final isVisible = map['isVisible'] == true;
        final isMinimized = map['isMinimized'] == true;
        return isVisible && !isMinimized;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _markSeenIfConversationIsVisible() async {
    if (!mounted) {
      return;
    }
    final activeConversationId = ref.read(activeConversationIdProvider);
    if (activeConversationId != _conversationId) {
      return;
    }
    final isActuallyVisible = await _isConversationActuallyVisible();
    if (!mounted || !isActuallyVisible) {
      return;
    }
    await ref
        .read(conversationMessagesControllerProvider(_conversationId).notifier)
        .markSeen();
  }

  void _markConversationSeenForLatestMessage(
    List<ChatMessage> messages, {
    bool force = false,
  }) {
    if (messages.isEmpty) {
      return;
    }
    final currentUserId = widget.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }
    final latestMessage = messages.first;
    if (!force &&
        (latestMessage.sender?.id == currentUserId ||
            latestMessage.id == _lastSeenMessageId)) {
      return;
    }

    _lastSeenMessageId = latestMessage.id;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_markSeenIfConversationIsVisible()),
    );
  }

  Future<void> _openRemoteDesktopForPeer() async {
    var peerDevice = _remotePeerDevice;
    var ip = normalizeIpAddress(peerDevice?.localIp);
    if (ip.isEmpty) {
      _showChatSnackBar('جارٍ جلب عنوان IP لجهاز المستخدم...');
      peerDevice = await _refreshRemotePeerDevice();
      ip = normalizeIpAddress(peerDevice?.localIp);
    }
    if (ip.isEmpty) {
      _showChatSnackBar(
        'لا يوجد عنوان IP مسجل لهذا المستخدم الآن. تأكد من تشغيل التطبيق على جهازه.',
      );
      return;
    }

    if (kIsWeb) {
      try {
        final ok = await web_bridge.electronOpenRdp(ip);
        if (ok) {
          _showChatSnackBar('تم فتح Remote Desktop ($ip)');
        } else {
          _showChatSnackBar('تعذر فتح Remote Desktop.');
        }
      } catch (e) {
        _showChatSnackBar('خطأ: $e');
      }
      return;
    }

    if (!Platform.isWindows) {
      _showChatSnackBar('فتح Remote Desktop متاح على ويندوز فقط.');
      return;
    }
    try {
      await Process.start('mstsc.exe', ['/v:$ip'], runInShell: true);
      _showChatSnackBar('تم فتح Remote Desktop ($ip)');
    } catch (error) {
      _showChatSnackBar(error.toString());
    }
  }

  Future<void> _probeRemotePeerConnectivity() async {
    var peerDevice = _remotePeerDevice;
    var ip = normalizeIpAddress(peerDevice?.localIp);
    if (ip.isEmpty) {
      _showChatSnackBar('جارٍ جلب عنوان IP لجهاز المستخدم...');
      peerDevice = await _refreshRemotePeerDevice();
      ip = normalizeIpAddress(peerDevice?.localIp);
    }
    if (ip.isEmpty) {
      _showChatSnackBar(
        'لا يوجد عنوان IP مسجل لهذا المستخدم الآن. تأكد من تشغيل التطبيق على جهازه.',
      );
      return;
    }

    if (kIsWeb) {
      try {
        final ok = await web_bridge.electronOpenPing(ip);
        if (ok) {
          _showChatSnackBar('تم فتح نافذة الفحص (Ping $ip)...');
        } else {
          _showChatSnackBar('تعذر فتح نافذة Terminal.');
        }
      } catch (e) {
        _showChatSnackBar('خطأ: $e');
      }
      return;
    }

    if (!Platform.isWindows) {
      _showChatSnackBar('فحص الاتصال عبر Terminal متاح على ويندوز فقط.');
      return;
    }
    try {
      await Process.start(
        'cmd.exe',
        ['/c', 'start', 'cmd.exe', '/k', 'ping', ip],
        runInShell: true,
      );
      _showChatSnackBar('تم فتح نافذة الفحص (Ping $ip)...');
    } catch (error) {
      _showChatSnackBar(error.toString());
    }
  }

  // ── Scroll ─────────────────────────────────────────────────────────────────
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isNear = _isNearBottom();
    final shouldShowButton = !isNear;
    if (isNear && mounted) {
      if (_unreadBelowCount > 0) {
        setState(() {
          _unreadBelowCount = 0;
        });
      }
      final currentMessages = ref
          .read(conversationMessagesControllerProvider(_conversationId))
          .valueOrNull
          ?.messages;
      if (currentMessages != null && currentMessages.isNotEmpty) {
        _markConversationSeenForLatestMessage(currentMessages);
      }
    }
    if (shouldShowButton != _showScrollToBottomButton && mounted) {
      setState(() {
        _showScrollToBottomButton = shouldShowButton;
      });
    }
    final messagesData = ref
        .read(conversationMessagesControllerProvider(_conversationId))
        .valueOrNull;
    final canLoadMore =
        (messagesData?.hasMore ?? false) &&
        !(messagesData?.isLoadingMore ?? false);
    if (!canLoadMore) return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref
          .read(
            conversationMessagesControllerProvider(_conversationId).notifier,
          )
          .loadMore();
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels < 50;
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scrollController.hasClients) return;
    if (mounted && (_showScrollToBottomButton || _unreadBelowCount > 0)) {
      setState(() {
        _showScrollToBottomButton = false;
        _unreadBelowCount = 0;
      });
    }
    final currentMessages = ref
        .read(conversationMessagesControllerProvider(_conversationId))
        .valueOrNull
        ?.messages;
    if (currentMessages != null && currentMessages.isNotEmpty) {
      _markConversationSeenForLatestMessage(currentMessages);
    }
    if (jump) {
      _scrollController.jumpTo(0);
    } else {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ── Search ─────────────────────────────────────────────────────────────────
  void _openSearch() {
    if (!mounted) return;
    setState(() {
      _showSearch = true;
      _activeSearchMatchIndex = 0;
      _focusedMessageId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  bool get _selectionMode => _selectedMessageIds.isNotEmpty;

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _clearSelection() {
    if (_selectedMessageIds.isEmpty) {
      return;
    }
    setState(_selectedMessageIds.clear);
  }

  Future<void> _scrollToTargetWithRetry(String targetId) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!mounted) return;
      await Future.delayed(Duration(milliseconds: attempt == 0 ? 350 : 250));
      if (!mounted) return;

      final messages = ref
          .read(conversationMessagesControllerProvider(_conversationId))
          .valueOrNull
          ?.messages;

      if (messages != null && messages.isNotEmpty) {
        final found = messages.any((m) => m.id == targetId);
        if (found) {
          if (mounted) {
            setState(() {
              _focusedMessageId = targetId;
            });
          }
          await _scrollToMessageById(targetId);
          _focusedMessageClearTimer?.cancel();
          _focusedMessageClearTimer = Timer(const Duration(seconds: 4), () {
            if (mounted && _focusedMessageId == targetId) {
              setState(() => _focusedMessageId = null);
            }
          });
          return;
        } else {
          final hasMore = ref
              .read(conversationMessagesControllerProvider(_conversationId))
              .valueOrNull
              ?.hasMore ?? false;
          if (hasMore) {
            await ref
                .read(conversationMessagesControllerProvider(_conversationId).notifier)
                .loadMore();
          } else {
            break;
          }
        }
      }
    }
  }

  Future<void> _scrollToMessageById(String messageId) async {
    var key = _messageKeys[messageId];
    var targetContext = key?.currentContext;
    if (targetContext == null && _scrollController.hasClients) {
      final messages = ref
          .read(conversationMessagesControllerProvider(_conversationId))
          .valueOrNull
          ?.messages;
      if (messages != null && messages.isNotEmpty) {
        final targetIndex = messages.indexWhere((m) => m.id == messageId);
        if (targetIndex >= 0) {
          final maxExt = _scrollController.position.maxScrollExtent;
          if (maxExt > 0) {
            final ratio = (targetIndex / messages.length).clamp(0.0, 1.0);
            _scrollController.jumpTo(ratio * maxExt);
            await WidgetsBinding.instance.endOfFrame;
            if (!mounted) return;
            key = _messageKeys[messageId];
            targetContext = key?.currentContext;
          }
        }
      }
    }
    if (targetContext == null || !targetContext.mounted) {
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
  }

  void _navigateSearchResult(List<ChatMessage> matches, int delta) {
    if (matches.isEmpty) {
      return;
    }
    setState(() {
      _activeSearchMatchIndex =
          (_activeSearchMatchIndex + delta) % matches.length;
      if (_activeSearchMatchIndex < 0) {
        _activeSearchMatchIndex = matches.length - 1;
      }
      _focusedMessageId = matches[_activeSearchMatchIndex].id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMessageById(matches[_activeSearchMatchIndex].id);
    });
  }

  Map<String, dynamic>? _replyMetadata(ChatMessage? replyTarget) {
    if (replyTarget == null) {
      return null;
    }

    // For poll/checklist messages, derive preview from question field in metadata
    String previewContent = replyTarget.content;
    if (previewContent.isEmpty) {
      if (replyTarget.messageType == 'poll') {
        final question = replyTarget.metadata?['question']?.toString();
        previewContent = question != null && question.isNotEmpty
            ? '📊 $question'
            : '📊 استطلاع رأي';
      } else if (replyTarget.messageType == 'checklist') {
        final question = replyTarget.metadata?['question']?.toString();
        previewContent = question != null && question.isNotEmpty
            ? '✅ $question'
            : '✅ قائمة مهام';
      } else if (replyTarget.fileName != null &&
          replyTarget.fileName!.isNotEmpty) {
        previewContent = replyTarget.fileName!;
      }
    }

    return {
      'replyPreview': {
        'senderId': replyTarget.sender?.id ?? replyTarget.senderId,
        'senderName': replyTarget.sender?.displayName ?? 'عضو',
        'content': previewContent,
        'fileName': replyTarget.fileName,
        'messageType': replyTarget.messageType,
      },
    };
  }

  Map<String, dynamic> _forwardMetadataFor(ChatMessage message) {
    return {
      'forwardedFrom': {
        'conversationId': message.conversationId,
        'conversationName': widget.conversation.displayTitle(
          widget.currentUser?.id ?? '',
        ),
        'senderId': message.sender?.id ?? message.senderId,
        'senderName': message.sender?.displayName ?? 'عضو',
        'messageId': message.id,
        'messageType': message.messageType,
        'forwardedAt': DateTime.now().toUtc().toIso8601String(),
      },
    };
  }

  Future<Map<String, dynamic>?> _pickBroadcastTargetsMetadata() async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final liveConversation =
        overview?.conversations
            .where((entry) => entry.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (liveConversation.type != 'broadcast') {
      return null;
    }

    final departments = overview?.departments ?? const <DepartmentSummary>[];
    final users = overview?.users ?? const <ChatDirectoryUser>[];

    if (!mounted) return null;

    final result = await BroadcastTargetPickerDialog.show(
      context,
      departments: departments,
      users: users,
      currentUserId: widget.currentUser?.id ?? '',
      initialSendToAll: _broadcastSendToAllDepartments,
      initialDepartmentIds: _broadcastTargetDepartmentIds,
      initialUserIds: _broadcastTargetUserIds,
      token: widget.token,
    );

    if (result == null) {
      return null;
    }

    final broadcastTargets =
        result['broadcastTargets'] as Map<String, dynamic>?;
    if (broadcastTargets != null) {
      _broadcastSendToAllDepartments =
          broadcastTargets['sentToAllDepartments'] == true;
      _broadcastTargetDepartmentIds = Set<String>.from(
        (broadcastTargets['departmentIds'] as List? ?? []),
      );
      _broadcastTargetUserIds = Set<String>.from(
        (broadcastTargets['userIds'] as List? ?? []),
      );
    }

    return result;
  }

  Future<void> _jumpToSearchMessage(
    ChatMessage message, {
    String? query,
  }) async {
    await ref
        .read(conversationMessagesControllerProvider(_conversationId).notifier)
        .hydrateMessages([message]);
    if (!mounted) {
      return;
    }
    setState(() {
      _showSearch = true;
      if (query != null && query.trim().isNotEmpty) {
        _searchController.text = query.trim();
      }
      _focusedMessageId = message.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMessageById(message.id);
    });
  }

  Future<void> _showRemoteSearchDialog() async {
    final query = _searchController.text.trim();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => ChatRemoteSearchDialog(
        conversationId: _conversationId,
        initialQuery: query.isNotEmpty ? query : null,
        onSelectMessage: (message) async {
          Navigator.of(dialogContext).pop();
          await _jumpToSearchMessage(
            message,
            query: _searchController.text.trim().isNotEmpty
                ? _searchController.text.trim()
                : null,
          );
        },
      ),
    );
  }

  Future<void> _forwardSingleMessage(ChatMessage message) async {
    await _forwardMessages([message]);
  }

  Future<void> _forwardSelectedMessages(List<ChatMessage> allMessages) async {
    final selectedMessages =
        allMessages
            .where((message) => _selectedMessageIds.contains(message.id))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (selectedMessages.isEmpty) {
      return;
    }
    await _forwardMessages(selectedMessages);
  }

  Future<void> _forwardMessages(List<ChatMessage> messagesToForward) async {
    if (messagesToForward.isEmpty) {
      return;
    }

    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    if (overview == null) {
      return;
    }

    final targets = await ChatForwardDialog.show(
      context,
      currentUserId: widget.currentUser?.id ?? '',
      currentConversationId: _conversationId,
      selectedMessageCount: messagesToForward.length,
      token: widget.token,
    );

    if (targets == null || targets.isEmpty) {
      return;
    }

    // Filter restricted attachments
    var skippedRestrictedCount = 0;
    final validMessages = <ChatMessage>[];
    for (final message in messagesToForward) {
      if (!message.attachmentForwardAllowed || message.metadata?['allowForward'] == false) {
        skippedRestrictedCount++;
      } else {
        validMessages.add(message);
      }
    }

    if (validMessages.isEmpty) {
      if (mounted && skippedRestrictedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skippedRestrictedCount == 1
                  ? 'المرسل منع إعادة توجيه هذه الرسالة.'
                  : 'تم تخطي $skippedRestrictedCount رسائل لأن المرسل منع إعادة توجيهها.',
            ),
          ),
        );
      }
      return;
    }

    final repository = ref.read(chatRepositoryProvider);
    final targetConversationIds = <String>{};
    final targetNames = <String>[];

    // Show loading indicator
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('جاري إعادة توجيه الرسائل...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    for (final target in targets) {
      try {
        switch (target.kind) {
          case ForwardTargetKind.conversation:
            if (target.conversation != null) {
              targetConversationIds.add(target.conversation!.id);
              targetNames.add(target.title);
            }
            break;

          case ForwardTargetKind.user:
            if (target.user != null) {
              // Check if direct conversation already exists in overview
              ChatConversation? existingDirect;
              for (final conv in overview.conversations) {
                if (conv.type == 'direct') {
                  final isWithTarget = conv.members.any((m) => m.id == target.user!.id);
                  if (isWithTarget) {
                    existingDirect = conv;
                    break;
                  }
                }
              }

              if (existingDirect != null) {
                targetConversationIds.add(existingDirect.id);
              } else {
                final created = await repository.createDirectConversation(target.user!.id);
                targetConversationIds.add(created.id);
              }
              targetNames.add(target.title);
            }
            break;

          case ForwardTargetKind.department:
            if (target.department != null) {
              final dept = target.department!;
              // 1. Try to find room conversation for this department
              ChatConversation? deptRoom;
              for (final conv in overview.conversations) {
                if (conv.departmentId == dept.id || conv.id == dept.defaultConversationId) {
                  deptRoom = conv;
                  break;
                }
              }

              if (deptRoom != null) {
                targetConversationIds.add(deptRoom.id);
                targetNames.add('غرفة ${dept.name}');
              } else {
                // If no room conversation exists, forward to each user in this department!
                final deptUsers = overview.users.where((u) =>
                  (u.departmentId == dept.id || u.departmentIds.contains(dept.id)) &&
                  u.id != (widget.currentUser?.id ?? '')
                ).toList();

                if (deptUsers.isEmpty) {
                  targetNames.add(dept.name);
                } else {
                  targetNames.add('${dept.name} (${deptUsers.length} أعضاء)');
                  for (final member in deptUsers) {
                    ChatConversation? memberConv;
                    for (final conv in overview.conversations) {
                      if (conv.type == 'direct' && conv.members.any((m) => m.id == member.id)) {
                        memberConv = conv;
                        break;
                      }
                    }
                    if (memberConv != null) {
                      targetConversationIds.add(memberConv.id);
                    } else {
                      try {
                        final created = await repository.createDirectConversation(member.id);
                        targetConversationIds.add(created.id);
                      } catch (_) {}
                    }
                  }
                }
              }
            }
            break;
        }
      } catch (err) {
        debugPrint('Error resolving forward target: $err');
      }
    }

    if (targetConversationIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديد وجهة إعادة التوجيه')),
        );
      }
      return;
    }

    try {
      for (final convId in targetConversationIds) {
        for (final message in validMessages) {
          final metadata = _forwardMetadataFor(message);
          await repository.forwardMessage(
            conversationId: convId,
            sourceMessageId: message.id,
            metadata: metadata,
          );
        }
      }

      unawaited(ref.read(chatOverviewControllerProvider.notifier).refresh());

      if (!mounted) return;
      _clearSelection();

      final destinationText = targetNames.length <= 2
          ? targetNames.join(' و ')
          : '${targetNames.first} و ${targetNames.length - 1} وجهات أخرى';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تمت إعادة توجيه ${validMessages.length} رسالة إلى $destinationText بنجاح',
          ),
          backgroundColor: const Color(0xFF34C759),
        ),
      );

      if (skippedRestrictedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تخطي $skippedRestrictedCount مرفق لأن المرسل منع إعادة توجيهه.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء إعادة التوجيه: $error')),
      );
    }
  }

  // ── Typing ─────────────────────────────────────────────────────────────────
  void _stopTypingNow() {
    _stopTypingTimer?.cancel();
    _stopTypingTimer = null;
    if (!_isTyping) {
      return;
    }
    _isTyping = false;
    ref
        .read(conversationMessagesControllerProvider(_conversationId).notifier)
        .stopTyping();
  }

  void _scheduleStopTyping() {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final conversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (_isReadOnlyConversation(conversation)) return;
    final notifier = ref.read(
      conversationMessagesControllerProvider(_conversationId).notifier,
    );
    final hasText = _messageController.text.trim().isNotEmpty;
    if (!hasText) {
      _stopTypingNow();
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      notifier.sendTyping();
    }
    _stopTypingTimer?.cancel();
    _stopTypingTimer = Timer(const Duration(seconds: 2), _stopTypingNow);
  }

  List<String> _extractMentions(String text) {
    if (widget.conversation.type != 'group' &&
        widget.conversation.type != 'department') {
      return const [];
    }
    final mentions = <String>[];
    final regex = RegExp(r'@([A-Za-z0-9_]+)');
    for (final match in regex.allMatches(text)) {
      final username = match.group(1);
      if (username == null) continue;
      if (username.toLowerCase() == 'all') {
        mentions.addAll(widget.conversation.members.map((m) => m.id));
        continue;
      }
      try {
        final user = widget.conversation.members.firstWhere(
          (m) => m.username.toLowerCase() == username.toLowerCase(),
        );
        mentions.add(user.id);
      } catch (_) {}
    }
    return mentions.toSet().toList(); // Ensure unique mentions
  }

  // ── Send ───────────────────────────────────────────────────────────────────
  Future<void> _sendText({
    bool isSilent = false,
    DateTime? scheduledFor,
  }) async {
    if (_isSendingText) return;

    if (_isUploadingAttachment) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('انتظر حتى يكتمل رفع الملف الحالي أولًا.'),
          ),
        );
      }
      return;
    }

    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final conversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (_isReadOnlyConversation(conversation)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readOnlyBannerText(conversation))),
        );
      }
      return;
    }

    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final broadcastMetadata = await _pickBroadcastTargetsMetadata();
    if (conversation.type == 'broadcast' && broadcastMetadata == null) {
      return;
    }
    final payloadMetadata = <String, dynamic>{
      ...?_replyMetadata(_replyingTo),
      ...?broadcastMetadata,
      if (_extractMentions(content).isNotEmpty)
        'mentions': _extractMentions(content),
    };

    final notifier = ref.read(
      conversationMessagesControllerProvider(_conversationId).notifier,
    );

    _isSendingText = true;
    final wasEditing = _editingMessage != null;
    final targetEditingMessage = _editingMessage;
    final targetReplyingTo = _replyingTo;

    // Immediately clear text field and reset composer state for instant UI response
    // and to prevent any duplicate sending while network request is in flight.
    _messageController.clear();
    unawaited(_draftStore.clear(_conversationId));
    _stopTypingNow();
    if (mounted) {
      setState(() {
        _replyingTo = null;
        _editingMessage = null;
      });
      _scrollToBottom();
      _messageFocusNode.requestFocus();
    }

    try {
      if (wasEditing && targetEditingMessage != null) {
        await notifier.editMessage(
          messageId: targetEditingMessage.id,
          content: content,
        );
      } else {
        await notifier.sendText(
          content,
          replyToMessageId: targetReplyingTo?.id,
          metadata: payloadMetadata.isEmpty ? null : payloadMetadata,
          isSilent: isSilent,
          scheduledFor: scheduledFor,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل الإرسال: لا يوجد اتصال بالسيرفر حالياً.'),
          ),
        );
      }
    } finally {
      _isSendingText = false;
    }
  }

  void _showMessageDetails(ChatMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'من شاهد الرسالة',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SizedBox(
          width: 400,
          height: 400,
          child: FutureBuilder<Map<String, dynamic>>(
            future: ref
                .read(chatRepositoryProvider)
                .getReadReceipts(message.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('خطأ: ${snapshot.error}'));
              }
              final seenBy = snapshot.data?['seenBy'] as List<dynamic>? ?? [];
              if (seenBy.isEmpty) {
                return const Center(child: Text('لم يشاهدها أحد بعد.'));
              }
              return ListView.builder(
                itemCount: seenBy.length,
                itemBuilder: (context, index) {
                  final user = seenBy[index] as Map<String, dynamic>;
                  return ListTile(
                    leading: SafeNetworkAvatar(
                      imageUrl: user['avatarUrl']?.toString() ?? '',
                      radius: 18,
                      fallbackText:
                          user['displayName']?.toString().isNotEmpty == true
                          ? user['displayName'].toString()[0].toUpperCase()
                          : '?',
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                    ),
                    title: Text(user['displayName']?.toString() ?? 'مستخدم'),
                    subtitle: user['seenAt'] != null
                        ? Text(
                            DateTime.parse(
                              user['seenAt'].toString(),
                            ).toLocal().toString(),
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showScheduledMessages() {
    ScheduledMessagesDialog.show(
      context,
      conversationId: _conversationId,
      onMessageSent: () {
        ref
            .read(conversationMessagesControllerProvider(_conversationId).notifier)
            .refresh();
      },
    );
  }

  void _showSendOptions() {
    final hasContent = _messageController.text.trim().isNotEmpty;
    if (!hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة نص الرسالة أولاً قبل جدولتها.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final now = DateTime.now();
    final today6PM = DateTime(now.year, now.month, now.day, 18, 0);
    final tomorrow9AM = DateTime(now.year, now.month, now.day + 1, 9, 0);

    showDialog(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final cardBg = isDark ? const Color(0xFF1E1E20) : Colors.white;
        final borderColor = isDark ? Colors.white12 : const Color(0xFFE5E5EA);

        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.send_rounded,
                            color: Color(0xFF007AFF),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'خيارات الإرسال المتقدمة',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, thickness: 0.6, color: borderColor),

                  // Option 1: Silent send
                  ListTile(
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.notifications_off_rounded, color: Colors.orange, size: 18),
                    ),
                    title: const Text('إرسال بدون صوت', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('يصل إشعار صامت للمستلم دون إصدار نغمة', style: TextStyle(fontSize: 12)),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _sendText(isSilent: true);
                    },
                  ),

                  Divider(height: 1, thickness: 0.6, color: borderColor),

                  // Presets title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'جدولة الرسالة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ),

                  // Preset 1: +30 minutes
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.timer_outlined, size: 20, color: Color(0xFF007AFF)),
                    title: const Text('بعد 30 دقيقة', style: TextStyle(fontSize: 13.5)),
                    trailing: Text(
                      DateFormat('hh:mm a', 'ar').format(now.add(const Duration(minutes: 30))),
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                    ),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _sendText(scheduledFor: now.add(const Duration(minutes: 30)));
                    },
                  ),

                  // Preset 2: +1 hour
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.timer_outlined, size: 20, color: Color(0xFF007AFF)),
                    title: const Text('بعد ساعة واحدة', style: TextStyle(fontSize: 13.5)),
                    trailing: Text(
                      DateFormat('hh:mm a', 'ar').format(now.add(const Duration(hours: 1))),
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                    ),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _sendText(scheduledFor: now.add(const Duration(hours: 1)));
                    },
                  ),

                  // Preset 3: Today 6 PM (if before 5:30 PM)
                  if (now.isBefore(today6PM.subtract(const Duration(minutes: 30))))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.nightlight_round, size: 20, color: Color(0xFF007AFF)),
                      title: const Text('مساء اليوم (06:00 م)', style: TextStyle(fontSize: 13.5)),
                      onTap: () {
                        Navigator.pop(dialogContext);
                        _sendText(scheduledFor: today6PM);
                      },
                    ),

                  // Preset 4: Tomorrow 9 AM
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.wb_sunny_rounded, size: 20, color: Color(0xFF007AFF)),
                    title: const Text('صباح الغد (09:00 ص)', style: TextStyle(fontSize: 13.5)),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _sendText(scheduledFor: tomorrow9AM);
                    },
                  ),

                  // Preset 5: Custom Date/Time
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.edit_calendar_rounded, size: 20, color: Color(0xFF007AFF)),
                    title: const Text('تحديد موعد مخصص...', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    onTap: () async {
                      Navigator.pop(dialogContext);
                      final selectedDate = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (selectedDate != null && mounted) {
                        final selectedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (selectedTime != null && mounted) {
                          final scheduledFor = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          );
                          if (scheduledFor.isAfter(DateTime.now())) {
                            _sendText(scheduledFor: scheduledFor);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('يجب أن يكون الوقت في المستقبل.'),
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendFile([String? droppedPath]) async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final conversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (_isReadOnlyConversation(conversation)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readOnlyBannerText(conversation))),
        );
      }
      return;
    }

    if (droppedPath != null && droppedPath.isNotEmpty) {
      await _sendPreparedFile(
        conversation: conversation,
        sendPath: droppedPath,
        displayName: p.basename(droppedPath),
        restrictForwardAndDownload: false,
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    if (kIsWeb) {
      await _sendPickedWebFiles(
        conversation: conversation,
        files: result.files,
        isImageBatch: false,
      );
      return;
    }

    final paths = result.files
        .map((entry) => entry.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();
    if (paths.isEmpty) {
      return;
    }

    if (paths.length == 1) {
      final singlePath = paths.first;
      if (!mounted) {
        return;
      }
      final sendDraft = await showAttachmentSendDialog(context, singlePath);
      if (sendDraft == null) {
        return;
      }
      await _sendPreparedFile(
        conversation: conversation,
        sendPath: sendDraft.filePath,
        displayName: sendDraft.displayName,
        restrictForwardAndDownload: sendDraft.restrictForwardAndDownload,
        caption: sendDraft.caption,
      );
      return;
    }

    final restrictForwardAndDownload = await _confirmBatchFileSend(paths);
    if (restrictForwardAndDownload == null) {
      return;
    }

    Map<String, dynamic>? fixedBroadcastMetadata;
    if (conversation.type == 'broadcast') {
      fixedBroadcastMetadata = await _pickBroadcastTargetsMetadata();
      if (fixedBroadcastMetadata == null) {
        return;
      }
    }

    int sentCount = 0;
    int skippedCount = 0;
    final mediaGroupId = 'album_${DateTime.now().microsecondsSinceEpoch}';
    for (final path in paths) {
      final success = await _sendPreparedFile(
        conversation: conversation,
        sendPath: path,
        displayName: p.basename(path),
        restrictForwardAndDownload: restrictForwardAndDownload,
        fixedBroadcastMetadata: fixedBroadcastMetadata,
        extraMetadata: {
          'mediaGroupId': mediaGroupId,
          'mediaGroupSize': paths.length,
        },
        showFailureSnackbar: false,
      );
      if (success) {
        sentCount++;
      } else {
        skippedCount++;
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skippedCount == 0
              ? 'تم إرسال $sentCount ملف.'
              : 'تم إرسال $sentCount ملف وتخطي $skippedCount ملف بسبب الحجم.',
        ),
      ),
    );
  }

  Future<void> _sendImage() async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final conversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (_isReadOnlyConversation(conversation)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readOnlyBannerText(conversation))),
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    if (kIsWeb) {
      await _sendPickedWebFiles(
        conversation: conversation,
        files: result.files,
        isImageBatch: true,
      );
      return;
    }

    final paths = result.files
        .map((entry) => entry.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();
    if (paths.isEmpty) {
      return;
    }

    if (paths.length == 1) {
      if (!mounted) {
        return;
      }
      final sendDraft = await showAttachmentSendDialog(context, paths.first);
      if (sendDraft == null) {
        return;
      }
      await _sendPreparedFile(
        conversation: conversation,
        sendPath: sendDraft.filePath,
        displayName: sendDraft.displayName,
        restrictForwardAndDownload: sendDraft.restrictForwardAndDownload,
        caption: sendDraft.caption,
      );
      return;
    }

    final restrictForwardAndDownload = await _confirmBatchFileSend(paths);
    if (restrictForwardAndDownload == null) {
      return;
    }

    Map<String, dynamic>? fixedBroadcastMetadata;
    if (conversation.type == 'broadcast') {
      fixedBroadcastMetadata = await _pickBroadcastTargetsMetadata();
      if (fixedBroadcastMetadata == null) {
        return;
      }
    }

    int sentCount = 0;
    int skippedCount = 0;
    final mediaGroupId = 'album_${DateTime.now().microsecondsSinceEpoch}';
    for (final path in paths) {
      final success = await _sendPreparedFile(
        conversation: conversation,
        sendPath: path,
        displayName: p.basename(path),
        restrictForwardAndDownload: restrictForwardAndDownload,
        fixedBroadcastMetadata: fixedBroadcastMetadata,
        showFailureSnackbar: false,
        extraMetadata: {
          'mediaGroupId': mediaGroupId,
          'mediaGroupSize': paths.length,
        },
      );
      if (success) {
        sentCount++;
      } else {
        skippedCount++;
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skippedCount == 0
              ? 'تم إرسال $sentCount صورة.'
              : 'تم إرسال $sentCount صورة وتخطي $skippedCount ملف بسبب الحجم.',
        ),
      ),
    );
  }

  Future<void> _createPoll() async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final conversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (_isReadOnlyConversation(conversation)) return;

    final pollData = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const PollCreatorDialog(),
    );

    if (pollData == null || !mounted) return;

    final metadata = {
      'question': pollData['question'],
      'isAnonymous': pollData['isAnonymous'],
      'isMultipleChoice': pollData['isMultipleChoice'],
      'options': pollData['options'],
      'votes': <String, dynamic>{},
    };

    try {
      await ref
          .read(
            conversationMessagesControllerProvider(_conversationId).notifier,
          )
          .sendMessage(
            content: '',
            messageType: 'poll',
            metadata: metadata,
            replyToMessageId: _replyingTo?.id,
          );
      if (mounted) {
        setState(() => _replyingTo = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create poll: $e')));
      }
    }
  }

  Future<void> _createChecklist() async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final conversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (_isReadOnlyConversation(conversation)) return;

    final pollData = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const PollCreatorDialog(isChecklistMode: true),
    );

    if (pollData == null || !mounted) return;

    final metadata = {
      'question': pollData['question'],
      'isAnonymous': false,
      'isMultipleChoice': true,
      'isChecklist': true,
      'options': pollData['options'],
      'votes': <String, dynamic>{},
    };

    try {
      await ref
          .read(
            conversationMessagesControllerProvider(_conversationId).notifier,
          )
          .sendMessage(
            content: '',
            messageType: 'checklist',
            metadata: metadata,
            replyToMessageId: _replyingTo?.id,
          );
      if (mounted) {
        setState(() => _replyingTo = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create checklist: $e')),
        );
      }
    }
  }

  Future<void> _openGifPicker() async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final conversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (_isReadOnlyConversation(conversation)) return;

    final sticker = await showDialog<LocalSticker>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const SizedBox(width: 500, height: 600, child: GifPickerPanel()),
      ),
    );

    if (sticker != null && mounted) {
      await _sendPreparedFile(
        conversation: conversation,
        sendPath: sticker.name,
        displayName: sticker.name,
        sourceFileName: sticker.name,
        fileBytes: sticker.bytes,
        restrictForwardAndDownload: false,
        isSticker: true,
      );
    }
  }

  Future<void> _votePoll(String messageId, List<String> optionIds) async {
    try {
      await ref
          .read(
            conversationMessagesControllerProvider(_conversationId).notifier,
          )
          .votePoll(messageId, optionIds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to vote: $e')));
      }
    }
  }

  Future<void> _exportPoll(String messageId) async {
    try {
      final file = await ref
          .read(chatRepositoryProvider)
          .downloadPollExport(messageId);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open file: ${result.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to export: $e')));
      }
    }
  }

  Future<void> _sendScreenshotFromOpenWindow() async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final conversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;
    if (_isReadOnlyConversation(conversation)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_readOnlyBannerText(conversation))),
        );
      }
      return;
    }

    // ignore: unused_local_variable
    final messagesState = ref.read(
      conversationMessagesControllerProvider(_conversationId),
    );

    final windows = await _listOpenDesktopWindows();
    if (!mounted) {
      return;
    }
    final selectedWindow = windows.isEmpty
        ? null
        : await _showDesktopWindowPicker(windows);
    if (!mounted || (windows.isNotEmpty && selectedWindow == null)) {
      return;
    }

    try {
      // ── Electron (kIsWeb): main process captures and returns base64 PNG ──
      if (kIsWeb) {
        final String? base64Png = selectedWindow == null
            ? await web_bridge.electronCaptureScreen()
            : await web_bridge.electronCaptureWindow(selectedWindow.windowId);

        if (base64Png == null || base64Png.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تعذر التقاط لقطة الشاشة.')),
            );
          }
          return;
        }

        final pngBytes = base64Decode(base64Png);
        final fileName =
            'screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
        await _sendPreparedFile(
          conversation: conversation,
          sendPath: fileName,
          fileBytes: pngBytes,
          displayName: fileName,
          restrictForwardAndDownload: false,
        );
        return;
      }

      // ── Native Windows: write to temp file then send ──
      final fileName =
          'screenshot_${DateTime.now().millisecondsSinceEpoch}.bmp';
      final targetPath = p.join(Directory.systemTemp.path, fileName);

      final captured = selectedWindow == null
          ? await _capturePrimaryScreen(targetPath)
          : await _captureSelectedWindow(selectedWindow, targetPath);
      if (!captured) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تعذر التقاط لقطة الشاشة. أعد فتح التطبيق بالكامل لو كان محدثًا للتو.',
              ),
            ),
          );
        }
        return;
      }

      final file = File(targetPath);
      if (!await file.exists()) {
        return;
      }

      var finalPath = targetPath;
      var finalName = fileName;
      try {
        final bmpBytes = await file.readAsBytes();
        final ui.Codec codec = await ui.instantiateImageCodec(bmpBytes);
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        final ui.Image image = frameInfo.image;
        final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (pngData != null) {
          final pngBytes = pngData.buffer.asUint8List();
          final pngFileName = fileName.replaceAll('.bmp', '.png');
          final pngPath = targetPath.replaceAll('.bmp', '.png');
          final pngFile = File(pngPath);
          await pngFile.writeAsBytes(pngBytes, flush: true);
          if (await pngFile.exists()) {
            finalPath = pngPath;
            finalName = pngFileName;
            unawaited(file.delete().catchError((_) => file));
          }
        }
      } catch (e) {
        debugPrint('Failed to compress BMP to PNG: $e');
      }

      await _sendPreparedFile(
        conversation: conversation,
        sendPath: finalPath,
        displayName: finalName,
        restrictForwardAndDownload: false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر التقاط لقطة الشاشة: $error')),
      );
    }
  }

  Future<bool> _captureSelectedWindow(
    _DesktopOpenWindow selectedWindow,
    String targetPath,
  ) async {
    // Note: Electron (kIsWeb) path is handled upstream in _sendScreenshotFromOpenWindow.
    return await _windowChannel.invokeMethod<bool>('captureWindowImage', {
          'windowId': selectedWindow.windowId,
          'imagePath': targetPath,
        }) ??
        false;
  }

  Future<bool> _capturePrimaryScreen(String targetPath) async {
    // Note: Electron (kIsWeb) path is handled upstream in _sendScreenshotFromOpenWindow.
    try {
      return await _windowChannel.invokeMethod<bool>(
            'capturePrimaryScreenImage',
            {'imagePath': targetPath},
          ) ??
          false;
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ميزة لقطة الشاشة تحتاج إعادة تشغيل كاملة للتطبيق بعد التحديث.',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<List<_DesktopOpenWindow>> _listOpenDesktopWindows() async {
    try {
      List<Map<String, dynamic>> rawList;
      if (kIsWeb) {
        rawList = await web_bridge.electronListOpenWindows();
      } else {
        final result = await _windowChannel.invokeMethod<dynamic>(
          'listOpenWindows',
        );
        if (result is! List) {
          return const <_DesktopOpenWindow>[];
        }
        rawList = result
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return rawList
          .map((entry) {
            final rawId = entry['windowId'];
            final windowId = rawId is int ? rawId : int.tryParse('$rawId');
            final rawTitle = entry['title']?.toString().trim() ?? '';
            final title = rawTitle.isNotEmpty ? rawTitle : 'Untitled window';
            final appName = entry['appName']?.toString().trim() ?? '';
            if (windowId == null || windowId <= 0) {
              return null;
            }
            return _DesktopOpenWindow(
              windowId: windowId,
              title: title,
              appName: appName,
            );
          })
          .whereType<_DesktopOpenWindow>()
          .toList(growable: false)
        ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    } catch (_) {
      return const <_DesktopOpenWindow>[];
    }
  }

  Future<_DesktopOpenWindow?> _showDesktopWindowPicker(
    List<_DesktopOpenWindow> windows,
  ) {
    return showDialog<_DesktopOpenWindow>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final listController = ScrollController();
        return Dialog(
          child: SizedBox(
            width: 560,
            height: 520,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اختَر البرنامج المطلوب تصويره',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اضغط على البرنامج وسيتم إرسال لقطة الشاشة مباشرة.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : const Color(0xFF6E7B88),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white12
                              : const Color(0xFFE3E9F0),
                        ),
                      ),
                      child: Scrollbar(
                        controller: listController,
                        thumbVisibility: true,
                        child: ListView.separated(
                          controller: listController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: windows.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white10
                                : const Color(0xFFF0F3F7),
                          ),
                          itemBuilder: (context, index) {
                            final window = windows[index];
                            final subtitle = window.appName.isEmpty
                                ? window.title
                                : '${window.appName} - ${window.title}';
                            return ListTile(
                              dense: true,
                              leading: _buildWindowIcon(window, isDark: isDark),
                              title: Text(
                                window.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white60
                                      : const Color(0xFF6E7B88),
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: isDark
                                    ? Colors.white38
                                    : const Color(0xFF9AA7B6),
                              ),
                              onTap: () => Navigator.of(context).pop(window),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWindowIcon(_DesktopOpenWindow window, {required bool isDark}) {
    final key = '${window.appName} ${window.title}'.toLowerCase();
    IconData icon = Icons.apps_rounded;
    Color color = const Color(0xFF2F80ED);

    if (key.contains('chrome') ||
        key.contains('edge') ||
        key.contains('firefox')) {
      icon = Icons.public_rounded;
      color = const Color(0xFF2D9CDB);
    } else if (key.contains('explorer') || key.contains('folder')) {
      icon = Icons.folder_open_rounded;
      color = const Color(0xFFF2B94E);
    } else if (key.contains('word')) {
      icon = Icons.description_rounded;
      color = const Color(0xFF2F80ED);
    } else if (key.contains('excel')) {
      icon = Icons.table_chart_rounded;
      color = const Color(0xFF27AE60);
    } else if (key.contains('powerpoint')) {
      icon = Icons.slideshow_rounded;
      color = const Color(0xFFEB5757);
    } else if (key.contains('code') || key.contains('visual studio')) {
      icon = Icons.code_rounded;
      color = const Color(0xFF9B51E0);
    } else if (key.contains('notepad') || key.contains('text')) {
      icon = Icons.notes_rounded;
      color = const Color(0xFF56CCF2);
    }

    final bg = isDark
        ? color.withValues(alpha: 0.24)
        : color.withValues(alpha: 0.14);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: color),
    );
  }

  Future<void> _showComposerReactionPicker() async {
    final messagesState = ref
        .read(conversationMessagesControllerProvider(_conversationId))
        .valueOrNull;
    ChatMessage? target = _replyingTo;
    if (target == null) {
      final messages = messagesState?.messages ?? const <ChatMessage>[];
      for (final message in messages.reversed) {
        if (!message.isDeleted) {
          target = message;
          break;
        }
      }
    }

    if (target == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد رسالة متاحة لإضافة رياكت عليها.'),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    final messageId = target.id;
    await showChatReactionPickerDialog(
      context: context,
      onReact: (unicode) async {
        await ref
            .read(
              conversationMessagesControllerProvider(_conversationId).notifier,
            )
            .toggleReaction(messageId: messageId, emoji: unicode);
      },
    );
  }

  Future<void> _sendPickedWebFiles({
    required ChatConversation conversation,
    required List<PlatformFile> files,
    required bool isImageBatch,
  }) async {
    final usableFiles = files
        .where((entry) => entry.bytes != null && entry.bytes!.isNotEmpty)
        .toList();
    if (usableFiles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر قراءة الملفات من المتصفح.')),
        );
      }
      return;
    }

    if (usableFiles.length == 1) {
      final file = usableFiles.single;
      await _sendPreparedFile(
        conversation: conversation,
        sendPath: file.name,
        displayName: file.name,
        restrictForwardAndDownload: false,
        fileBytes: file.bytes,
        sourceFileName: file.name,
        knownFileSize: file.size,
      );
      return;
    }

    final names = usableFiles.map((entry) => entry.name).toList();
    final restrictForwardAndDownload = await _confirmBatchFileSend(names);
    if (restrictForwardAndDownload == null) {
      return;
    }

    Map<String, dynamic>? fixedBroadcastMetadata;
    if (conversation.type == 'broadcast') {
      fixedBroadcastMetadata = await _pickBroadcastTargetsMetadata();
      if (fixedBroadcastMetadata == null) {
        return;
      }
    }

    int sentCount = 0;
    int skippedCount = 0;
    final mediaGroupId = isImageBatch
        ? 'album_${DateTime.now().microsecondsSinceEpoch}'
        : null;
    for (final file in usableFiles) {
      final success = await _sendPreparedFile(
        conversation: conversation,
        sendPath: file.name,
        displayName: file.name,
        restrictForwardAndDownload: restrictForwardAndDownload,
        fileBytes: file.bytes,
        sourceFileName: file.name,
        knownFileSize: file.size,
        fixedBroadcastMetadata: fixedBroadcastMetadata,
        showFailureSnackbar: false,
        extraMetadata: mediaGroupId == null
            ? null
            : {
                'mediaGroupId': mediaGroupId,
                'mediaGroupSize': usableFiles.length,
              },
      );
      if (success) {
        sentCount++;
      } else {
        skippedCount++;
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skippedCount == 0
              ? (isImageBatch
                    ? 'تم إرسال $sentCount صورة.'
                    : 'تم إرسال $sentCount ملف.')
              : 'تم إرسال $sentCount وتخطي $skippedCount بسبب الحجم أو نوع الملف.',
        ),
      ),
    );
  }

  Future<bool> _sendPreparedFile({
    required ChatConversation conversation,
    required String sendPath,
    required String displayName,
    required bool restrictForwardAndDownload,
    String? caption,
    Uint8List? fileBytes,
    String? sourceFileName,
    int? knownFileSize,
    Map<String, dynamic>? fixedBroadcastMetadata,
    Map<String, dynamic>? extraMetadata,
    bool isSticker = false,
    bool showFailureSnackbar = true,
  }) async {
    if (isChatAttachmentExtensionBlocked(sendPath)) {
      if (showFailureSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kChatBlockedAttachmentUserMessage)),
        );
      }
      return false;
    }

    final fileSize =
        knownFileSize ?? fileBytes?.length ?? await File(sendPath).length();
    if (fileSize > _maxChatAttachmentBytes()) {
      if (showFailureSnackbar && mounted) {
        _showChatAttachmentSizeExceededSnackbar();
      }
      return false;
    }

    final broadcastMetadata =
        fixedBroadcastMetadata ?? await _pickBroadcastTargetsMetadata();
    if (conversation.type == 'broadcast' && broadcastMetadata == null) {
      return false;
    }

    final metadata = <String, dynamic>{
      ...?_replyMetadata(_replyingTo),
      ...?broadcastMetadata,
      ...?extraMetadata,
      if (_extractMentions(displayName).isNotEmpty)
        'mentions': _extractMentions(displayName),
      'attachmentPolicy': {
        'allowDownload': !restrictForwardAndDownload,
        'allowForward': !restrictForwardAndDownload,
      },
      if (restrictForwardAndDownload)
        'allowForward': false,
      if (isSticker) 'sticker': true,
    };

    setState(() {
      _isUploadingAttachment = true;
      _uploadProgress = 0;
      _uploadingFileName = displayName;
    });

    try {
      await ref
          .read(
            conversationMessagesControllerProvider(_conversationId).notifier,
          )
          .sendFile(
            sendPath,
            fileBytes: fileBytes,
            sourceFileName: sourceFileName ?? displayName,
            content: caption,
            replyToMessageId: _replyingTo?.id,
            customFileName: displayName,
            metadata: metadata,
            onProgress: (sent, total) {
              if (!mounted) {
                return;
              }
              setState(() {
                _uploadProgress = total <= 0
                    ? 0
                    : (sent / total).clamp(0, 1).toDouble();
              });
            },
          );
      if (!mounted) {
        return true;
      }
      setState(() {
        _replyingTo = null;
        _editingMessage = null;
      });
      _scrollToBottom();
      return true;
    } catch (e) {
      if (showFailureSnackbar && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(messageFromChatDioError(e))));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAttachment = false;
          _uploadProgress = 0;
          _uploadingFileName = null;
        });
      }
    }
  }

  Future<bool?> _confirmBatchFileSend(List<String> paths) async {
    bool restrictForwardAndDownload = false;
    final imagePaths = kIsWeb
        ? <String>[]
        : paths
              .where((path) {
                final ext = p.extension(path).toLowerCase();
                return ext == '.png' ||
                    ext == '.jpg' ||
                    ext == '.jpeg' ||
                    ext == '.webp' ||
                    ext == '.gif';
              })
              .take(8)
              .toList();

    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('إرسال ${paths.length} ملفات'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imagePaths.isNotEmpty) ...[
                    const Text(
                      'معاينة الصور',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: imagePaths
                          .map(
                            (imagePath) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(imagePath),
                                width: 70,
                                height: 70,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'الملفات المحددة',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ...paths
                      .take(10)
                      .map(
                        (path) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${p.basename(path)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  if (paths.length > 10)
                    Text('... و ${paths.length - 10} ملف إضافي'),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: restrictForwardAndDownload,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('منع إعادة التوجيه والتحميل'),
                    onChanged: (value) => setDialogState(() {
                      restrictForwardAndDownload = value == true;
                    }),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(restrictForwardAndDownload),
              child: const Text('إرسال'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAttachment(
    ChatMessage message, {
    bool openAfterDownload = false,
    bool forceSaveAs = false,
  }) async {
    if (!message.attachmentDownloadAllowed) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('هذا المرفق للعرض فقط. المرسل منع التحميل.'),
        ),
      );
      return;
    }
    try {
      if (mounted) {
        setState(() {
          _isDownloadingAttachment = true;
          _downloadProgress = 0;
          _downloadingFileName = message.fileName ?? 'مرفق';
        });
      }
      final localPath = await ref
          .read(chatRepositoryProvider)
          .downloadAttachment(
            message,
            onProgress: (received, total) {
              if (!mounted) {
                return;
              }
              setState(() {
                _downloadProgress = total <= 0
                    ? 0
                    : (received / total).clamp(0, 1).toDouble();
              });
            },
          );
      if (!mounted) {
        return;
      }

      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تنزيل ${message.fileName ?? 'المرفق'} من المتصفح.',
            ),
          ),
        );
        return;
      }

      if (forceSaveAs) {
        final suggestedName = p.basename(message.fileName ?? 'attachment');
        final destinationPath = await FilePicker.platform.saveFile(
          dialogTitle: 'حفظ الملف',
          fileName: suggestedName,
          lockParentWindow: true,
        );
        if (destinationPath == null || destinationPath.trim().isEmpty) {
          return;
        }
        await File(localPath).copy(destinationPath);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ ${message.fileName ?? 'المرفق'} بنجاح'),
          ),
        );
      } else if (openAfterDownload) {
        await OpenFilex.open(localPath);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تنزيل ${message.fileName ?? 'المرفق'} بنجاح'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().trim().isEmpty
                ? 'تعذر تنزيل المرفق حاليًا'
                : error.toString(),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloadingAttachment = false;
          _downloadProgress = 0;
          _downloadingFileName = null;
        });
      }
    }
  }

  Future<void> _saveReceivedSticker(ChatMessage message) async {
    if (!message.attachmentDownloadAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('غير مسموح بحفظ هذا المرفق.')),
        );
      }
      return;
    }
    try {
      Uint8List? bytes;
      try {
        final path = await ref
            .read(chatRepositoryProvider)
            .downloadAttachment(message);
        final file = File(path);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      } catch (_) {}

      bytes ??= await ref
          .read(chatRepositoryProvider)
          .fetchAttachmentBytes(message);

      if (bytes.isEmpty) {
        throw Exception('ملف الملصق فارغ');
      }

      await saveLocalSticker(
        name: message.fileName ?? 'sticker_${message.id.substring(0, 6)}.png',
        bytes: bytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت إضافة الملصق إلى مكتبة ملصقاتك بنجاح! ⭐'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ الملصق حاليًا.')),
        );
      }
    }
  }

  Future<void> _retryMessage(ChatMessage message) async {
    try {
      await ref
          .read(
            conversationMessagesControllerProvider(
              _conversationId,
            ).notifier,
          )
          .retryMessage(message);
    } catch (_) {
      // Handled and marked as failed by ConversationMessagesController
    }
  }

  Future<void> _openAttachment(ChatMessage message) {
    if (message.isImageMessage) {
      return _showImagePreview(message);
    }
    if (!message.attachmentDownloadAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذا الملف للعرض فقط داخل الشات.')),
        );
      }
      return Future<void>.value();
    }
    return _downloadAttachment(message, openAfterDownload: true);
  }

  Future<void> _printAttachment(ChatMessage message) async {
    if (!message.isPrintableAttachment) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('هذا النوع من الملفات غير قابل للطباعة.'),
          ),
        );
      }
      return;
    }
    if (!message.attachmentDownloadAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('المرسل منع طباعة هذا المرفق.')),
        );
      }
      return;
    }
    final fileUrl = message.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      return;
    }

    final downloadUrl = _downloadUrlFor(fileUrl);
    final prefs = ref.read(userPreferencesControllerProvider).valueOrNull;
    final result = await ref.read(desktopPrintServiceProvider).executePrintJob({
      'fileName': message.fileName ?? 'attachment',
      'mimeType': message.mimeType,
      'downloadUrl': downloadUrl,
      'source': 'chat_attachment_desktop',
    }, preferredPrinterName: prefs?.preferredPrinterName);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  String _downloadUrlFor(String fileUrl) {
    // Resolve to absolute URL first — server can return paths like
    // "api/chatmessages/.../file" without a leading slash, which would
    // produce malformed URLs like "http://ip:5000api/...".
    final resolved = resolveApiUrl(fileUrl.trim());
    final uri = Uri.tryParse(resolved);
    if (uri != null) {
      final segments = List<String>.from(uri.pathSegments);
      if (segments.isNotEmpty && segments.last == 'file') {
        segments[segments.length - 1] = 'download';
        return uri.replace(pathSegments: segments).toString();
      }
    }
    return resolved;
  }

  Future<void> _showImagePreview(ChatMessage message) async {
    if (!mounted || message.fileUrl == null || message.fileUrl!.isEmpty) {
      return;
    }

    final allMessages =
        ref
            .read(conversationMessagesControllerProvider(_conversationId))
            .valueOrNull
            ?.messages ??
        const <ChatMessage>[];
    final images = _albumFor(message, allMessages);
    final initialIndex = images
        .indexWhere((m) => m.id == message.id)
        .clamp(0, images.length - 1)
        .toInt();
    await showDialog<void>(
      context: context,
      builder: (context) => _FullscreenImageViewer(
        images: images,
        initialIndex: initialIndex,
        onDownload: (msg, ctx) => _startOverlayDownload(
          msg,
          overlayContext: ctx,
        ),
      ),
    );
  }

  List<ChatMessage> _collapseMediaAlbums(List<ChatMessage> messages) {
    final displayed = <ChatMessage>[];
    final groups = <String>{};
    for (final message in messages) {
      final groupId = message.isImageMessage
          ? (message.metadata?['mediaGroupId']?.toString())
          : null;
      if (groupId != null && groupId.isNotEmpty && !groups.add(groupId)) {
        continue;
      }
      displayed.add(message);
    }
    return displayed;
  }

  List<ChatMessage> _albumFor(ChatMessage message, List<ChatMessage> messages) {
    final groupId = message.metadata?['mediaGroupId']?.toString();
    if (!message.isImageMessage || groupId == null || groupId.isEmpty) {
      return <ChatMessage>[message];
    }
    final album = messages
        .where(
          (item) =>
              item.isImageMessage &&
              item.metadata?['mediaGroupId']?.toString() == groupId,
        )
        .toList();
    album.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return album;
  }

  void _startOverlayDownload(
    ChatMessage message, {
    required BuildContext overlayContext,
  }) {
    Navigator.of(overlayContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_downloadAttachment(message, forceSaveAs: true));
    });
  }

  String _formatDateDivider(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = today.difference(target).inDays;
    if (difference == 0) {
      return 'اليوم';
    } else if (difference == 1) {
      return 'أمس';
    } else {
      return DateFormat('yyyy/MM/dd').format(date);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String? _replyPreviewFor(
    ChatMessage message,
    Map<String, ChatMessage> messageById,
  ) {
    final replyId = message.replyToMessageId;
    if (replyId == null || replyId.isEmpty) return null;
    final replied = messageById[replyId];
    if (replied == null) return message.replyPreviewText ?? 'الرسالة الأصلية';
    if (replied.content.isNotEmpty) return replied.content;
    return replied.fileName ?? 'مرفق';
  }

  String? _replyPreviewSenderFor(
    ChatMessage message,
    Map<String, ChatMessage> messageById,
  ) {
    final replyId = message.replyToMessageId;
    if (replyId == null || replyId.isEmpty) {
      return null;
    }
    final replied = messageById[replyId];
    if (replied != null) {
      final senderName = replied.sender?.displayName ?? 'عضو';
      return senderName.trim().isEmpty ? null : senderName;
    }
    return message.replyPreviewSender;
  }

  Future<void> _showConversationGallery(List<ChatMessage> messages) async {
    final sharedImages = messages
        .where(
          (message) =>
              !message.isDeleted &&
              message.hasAttachment &&
              message.messageType == 'image',
        )
        .toList()
        .reversed
        .toList();
    final sharedFiles = messages
        .where(
          (message) =>
              !message.isDeleted &&
              message.hasAttachment &&
              message.messageType != 'image',
        )
        .toList()
        .reversed
        .toList();

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: DefaultTabController(
          length: 2,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'معرض المحادثة',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'استعراض الصور والملفات المشتركة في شاشة مستقلة.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _GalleryCountChip(
                        label: '${sharedImages.length} صور',
                        color: const Color(0xFF3390EC),
                      ),
                      const SizedBox(width: 8),
                      _GalleryCountChip(
                        label: '${sharedFiles.length} ملفات',
                        color: const Color(0xFF19A974),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: TabBar(
                    tabs: [
                      Tab(text: 'الصور'),
                      Tab(text: 'الملفات'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      sharedImages.isEmpty
                          ? const Center(child: Text('لا توجد صور مشتركة بعد'))
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 260,
                                    crossAxisSpacing: 14,
                                    mainAxisSpacing: 14,
                                    childAspectRatio: 1,
                                  ),
                              itemCount: sharedImages.length,
                              itemBuilder: (context, index) {
                                final message = sharedImages[index];
                                return InkWell(
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (context) => Dialog.fullscreen(
                                      backgroundColor: Colors.black,
                                      child: Stack(
                                        children: [
                                          Center(
                                            child: InteractiveViewer(
                                              child:
                                                  AuthenticatedAttachmentImage(
                                                    message: message,
                                                    fit: BoxFit.contain,
                                                  ),
                                            ),
                                          ),
                                          PositionedDirectional(
                                            top: 18,
                                            start: 18,
                                            child: IconButton.filledTonal(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              icon: const Icon(
                                                Icons.close_rounded,
                                              ),
                                            ),
                                          ),
                                          PositionedDirectional(
                                            top: 18,
                                            end: 18,
                                            child:
                                                message
                                                    .attachmentDownloadAllowed
                                                ? IconButton.filledTonal(
                                                    onPressed: () =>
                                                        _startOverlayDownload(
                                                          message,
                                                          overlayContext:
                                                              context,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.download_rounded,
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(18),
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          AuthenticatedAttachmentImage(
                                            message: message,
                                            fit: BoxFit.cover,
                                          ),
                                          PositionedDirectional(
                                            top: 10,
                                            end: 10,
                                            child:
                                                message
                                                    .attachmentDownloadAllowed
                                                ? IconButton.filledTonal(
                                                    onPressed: () =>
                                                        _startOverlayDownload(
                                                          message,
                                                          overlayContext:
                                                              context,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.download_rounded,
                                                      size: 18,
                                                    ),
                                                    style: IconButton.styleFrom(
                                                      backgroundColor: Colors
                                                          .black
                                                          .withValues(
                                                            alpha: 0.42,
                                                          ),
                                                      foregroundColor:
                                                          Colors.white,
                                                      minimumSize: const Size(
                                                        36,
                                                        36,
                                                      ),
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                          Positioned(
                                            left: 10,
                                            right: 10,
                                            bottom: 10,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.44,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                DateFormat('dd/MM/yyyy').format(
                                                  message.createdAt.toLocal(),
                                                ),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                      sharedFiles.isEmpty
                          ? const Center(
                              child: Text('لا توجد ملفات مشتركة بعد'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              itemCount: sharedFiles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final message = sharedFiles[index];
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  tileColor: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerLowest,
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(
                                      0xFF19A974,
                                    ).withValues(alpha: 0.12),
                                    child: Icon(
                                      _attachmentIcon(message.messageType),
                                      color: const Color(0xFF19A974),
                                    ),
                                  ),
                                  title: Text(message.fileName ?? 'مرفق'),
                                  subtitle: Text(
                                    DateFormat(
                                      'dd/MM/yyyy • HH:mm',
                                    ).format(message.createdAt.toLocal()),
                                  ),
                                  trailing: IconButton(
                                    onPressed: message.attachmentDownloadAllowed
                                        ? () => _startOverlayDownload(
                                            message,
                                            overlayContext: context,
                                          )
                                        : null,
                                    icon: Icon(
                                      message.attachmentDownloadAllowed
                                          ? Icons.download_rounded
                                          : Icons.lock_rounded,
                                    ),
                                    tooltip: message.attachmentDownloadAllowed
                                        ? 'تنزيل'
                                        : 'عرض فقط',
                                  ),
                                  onTap: () => _openAttachment(message),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusText(ChatConversation conversation) {
    if (_isBlockedFromSending(conversation)) return 'تم تقييدك: قراءة فقط';
    if (!conversation.isActive) return 'الغرفة معطّلة من قِبل المسؤول';
    if (_typingUsers.isNotEmpty) {
      if (_typingUsers.length == 1) return '${_typingUsers.first} يكتب...';
      return '${_typingUsers.length} أعضاء يكتبون...';
    }
    if (conversation.type != 'direct') {
      return '${conversation.members.length} عضو';
    }
    final peer = conversation.members
        .where((m) => m.id != widget.currentUser?.id)
        .cast<ChatDirectoryUser?>()
        .firstWhere((_) => true, orElse: () => null);
    if (peer == null) return 'محادثة خاصة';
    return formatPresenceLabel(peer);
  }

  Color _statusColor(ChatConversation conversation) {
    if (_isBlockedFromSending(conversation)) return const Color(0xFFF59E0B);
    if (!conversation.isActive) return const Color(0xFFF59E0B);
    if (_typingUsers.isNotEmpty) return const Color(0xFF3390EC);
    if (conversation.type != 'direct') {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }
    final peer = conversation.members
        .where((m) => m.id != widget.currentUser?.id)
        .cast<ChatDirectoryUser?>()
        .firstWhere((_) => true, orElse: () => null);
    if (peer == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    return presenceColor(peer.presenceStatus);
  }

  List<ChatMessage> _applySearch(List<ChatMessage> source) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((m) {
      final sender = (m.sender?.displayName ?? '').toLowerCase();
      final content = m.content.toLowerCase();
      final file = (m.fileName ?? '').toLowerCase();
      return sender.contains(query) ||
          content.contains(query) ||
          file.contains(query);
    }).toList();
  }

  bool _isBlockedFromSending(ChatConversation conversation) {
    final currentUserId = widget.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return false;
    }
    return conversation.blockedMemberIds.any((entry) => entry == currentUserId);
  }

  bool _isReadOnlyConversation(ChatConversation conversation) {
    return !conversation.isActive ||
        _isBlockedFromSending(conversation) ||
        !_canPublishInBroadcast(conversation);
  }

  String _readOnlyBannerText(ChatConversation conversation) {
    if (_isBlockedFromSending(conversation)) {
      return 'تم تقييدك في هذه المحادثة. يمكنك القراءة فقط.';
    }
    if (conversation.type == 'broadcast' &&
        !_canPublishInBroadcast(conversation)) {
      return 'هذه قناة بث. ليس لديك صلاحية الإرسال فيها.';
    }
    return 'هذه الغرفة معطّلة من قِبل المسؤول. يمكنك القراءة فقط.';
  }

  bool _canPublishInBroadcast(ChatConversation conversation) {
    if (conversation.type != 'broadcast') {
      return true;
    }
    final currentUserId = widget.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      return false;
    }
    if (conversation.createdBy == currentUserId) {
      return true;
    }
    if (conversation.admins.any((entry) => entry.id == currentUserId)) {
      return true;
    }
    return conversation.broadcastPublisherIds.contains(currentUserId);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    ref.listen(pendingChatDropFilesProvider, (prev, next) {
      if (next != null &&
          next['files'] != null &&
          next['conversationId'] == _conversationId) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final files = next['files'] as List<dynamic>;
          ref.read(pendingChatDropFilesProvider.notifier).state = null;

          final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
          final liveConversation =
              overview?.conversations
                  .where((c) => c.id == _conversationId)
                  .firstOrNull ??
              widget.conversation;

          if (_isReadOnlyConversation(liveConversation)) return;

          for (final file in files) {
            if (kIsWeb) {
              final bytes = await file.readAsBytes();
              await _sendPickedWebFiles(
                conversation: liveConversation,
                files: [
                  PlatformFile(
                    name: file.name,
                    size: bytes.length,
                    bytes: bytes,
                  ),
                ],
                isImageBatch: false,
              );
            } else {
              await _sendFile(file.path);
            }
          }
        });
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enterSendsMessage =
        ref
            .watch(userPreferencesControllerProvider)
            .valueOrNull
            ?.enterSendsMessage ??
        true;

    final overview = ref.watch(chatOverviewControllerProvider).valueOrNull;
    final liveConversation =
        overview?.conversations
            .where((c) => c.id == _conversationId)
            .firstOrNull ??
        widget.conversation;

    final messagesValue = ref.watch(
      conversationMessagesControllerProvider(_conversationId),
    );
    final messagesState = messagesValue.valueOrNull;
    final messages = messagesState?.messages ?? const <ChatMessage>[];
    final isReadOnly = _isReadOnlyConversation(liveConversation);
    final canManagePinnedMessage =
        liveConversation.type == 'group' &&
        liveConversation.createdBy == widget.currentUser?.id;
    final filteredMessages = _applySearch(messages);
    final hasSearchQuery = _searchController.text.trim().isNotEmpty;
    if (filteredMessages.isNotEmpty &&
        _activeSearchMatchIndex >= filteredMessages.length) {
      _activeSearchMatchIndex = 0;
    }
    final activeSearchMessageId =
        _focusedMessageId ??
        (hasSearchQuery && filteredMessages.isNotEmpty
            ? filteredMessages[_activeSearchMatchIndex].id
            : null);
    final messageById = <String, ChatMessage>{
      for (final m in messages) m.id: m,
    };

    if (messages.length != _lastMessageCount) {
      final isInitial = _lastMessageCount == 0;
      final isNear = _isNearBottom();
      final shouldScroll = !isInitial && isNear;
      final currentLatestMessageId =
          messages.isNotEmpty ? messages.first.id : null;

      if (!isInitial &&
          !isNear &&
          currentLatestMessageId != null &&
          currentLatestMessageId != _lastLatestMessageId) {
        var newMessagesAtBottom = 0;
        if (_lastLatestMessageId != null) {
          for (final msg in messages) {
            if (msg.id == _lastLatestMessageId) break;
            newMessagesAtBottom++;
          }
        } else {
          newMessagesAtBottom = 1;
        }
        if (newMessagesAtBottom > 0) {
          _unreadBelowCount += newMessagesAtBottom;
        }
      }
      _lastLatestMessageId = currentLatestMessageId;
      _lastMessageCount = messages.length;

      if (isNear) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _markConversationSeenForLatestMessage(messages);
          if (shouldScroll) {
            _scrollToBottom();
          }
        });
      }
    }

    final chatPreferences =
        widget.currentUser?.chatPreferences ?? ChatPreferences.defaults;
    final appearance = ChatAppearanceCatalog.resolveAppearance(
      preferences: chatPreferences,
      isDark: isDark,
      colorScheme: Theme.of(context).colorScheme,
    );

    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingFiles = true),
      onDragExited: (_) => setState(() => _draggingFiles = false),
      onDragDone: (details) async {
        setState(() => _draggingFiles = false);
        if (isReadOnly) return;
        for (final file in details.files) {
          if (kIsWeb) {
            final bytes = await file.readAsBytes();
            await _sendPickedWebFiles(
              conversation: widget.conversation,
              files: [
                PlatformFile(name: file.name, size: bytes.length, bytes: bytes),
              ],
              isImageBatch: false,
            );
          } else {
            await _sendFile(file.path);
          }
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: ChatBackdrop(preferences: chatPreferences, isDark: isDark),
          ),

          Column(
            children: [
              // ── Header ───────────────────────────────────────────────────
              _ChatHeader(
                conversation: liveConversation,
                currentUserId: widget.currentUser?.id ?? '',
                statusText: _selectionMode
                    ? '${_selectedMessageIds.length} محددة'
                    : _statusText(liveConversation),
                statusColor: _statusColor(liveConversation),
                onToggleInfoPanel: widget.onToggleRightPanel,
                onCloseConversation: widget.onCloseConversation,
                rightPanelVisible: widget.rightPanelVisible,
                onOpenSearch: _openSearch,
                onShowScheduled: _showScheduledMessages,
                onOpenGallery: () => _showConversationGallery(messages),
                onOpenRemoteSearch: _showRemoteSearchDialog,
                onOpenRemoteDesktop: _openRemoteDesktopForPeer,
                onProbePeerConnection: _probeRemotePeerConnectivity,
                hasRemotePeerDevice: normalizeIpAddress(
                  _remotePeerDevice?.localIp,
                ).isNotEmpty,
                remotePeerDevice: _remotePeerDevice,
                isResolvingRemotePeer: _isResolvingRemotePeer,
                selectionMode: _selectionMode,
                onClearSelection: _clearSelection,
                onForwardSelected: () => _forwardSelectedMessages(messages),
                isDark: isDark,
                appearance: appearance,
              ),

              if (liveConversation.pinnedMessage?.content.trim().isNotEmpty ==
                  true)
                GestureDetector(
                  onTap: () {
                    if (liveConversation.pinnedMessage!.messageId != null) {
                      _scrollToMessageById(
                        liveConversation.pinnedMessage!.messageId!,
                      );
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A2735)
                          : const Color(0xFFF4F8FC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF3390EC).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: Color(0xFF3390EC),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'رسالة مثبتة',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF3390EC),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(liveConversation.pinnedMessage!.content),
                            ],
                          ),
                        ),
                        if (canManagePinnedMessage)
                          IconButton(
                            tooltip: 'تعديل',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: widget.onToggleRightPanel,
                            icon: const Icon(Icons.edit_note_rounded, size: 20),
                          ),
                      ],
                    ),
                  ),
                ),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _selectionMode
                    ? Container(
                        key: const ValueKey('selection_bar'),
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        color: isDark
                            ? Color.lerp(
                                appearance.incomingBubbleColor,
                                const Color(0xFF18222D),
                                0.26,
                              )
                            : Color.lerp(
                                appearance.incomingBubbleColor,
                                const Color(0xFFF7FAFD),
                                0.72,
                              ),
                        child: Row(
                          children: [
                            Text(
                              'اختر محادثة الهدف لإعادة التوجيه أو ألغِ التحديد.',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF5C6F82),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // ── Search bar (animated) ────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _showSearch
                    ? _SearchBar(
                        key: const ValueKey('search_bar'),
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        totalMatches: filteredMessages.length,
                        activeMatchIndex: filteredMessages.isEmpty
                            ? 0
                            : _activeSearchMatchIndex + 1,
                        isDark: isDark,
                        appearance: appearance,
                        onPrevious: filteredMessages.isEmpty
                            ? null
                            : () => _navigateSearchResult(filteredMessages, -1),
                        onNext: filteredMessages.isEmpty
                            ? null
                            : () => _navigateSearchResult(filteredMessages, 1),
                        onClose: () => setState(() {
                          _showSearch = false;
                          _searchController.clear();
                          _activeSearchMatchIndex = 0;
                          _focusedMessageId = null;
                        }),
                        onOpenGlobalSearch: _showRemoteSearchDialog,
                      )
                    : const SizedBox.shrink(),
              ),

              // ── Messages ─────────────────────────────────────────────────
              Expanded(
                child: messagesValue.when(
                  skipLoadingOnReload: true,
                  skipLoadingOnRefresh: true,
                  loading: () => const _DesktopChatMessagesLoadingSkeleton(),
                  error: (error, _) => Center(child: Text(error.toString())),
                  data: (state) {
                    if (filteredMessages.isEmpty &&
                        _searchController.text.isNotEmpty) {
                      return Center(
                        child: Text(
                          'لا توجد رسائل مطابقة',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF708499),
                          ),
                        ),
                      );
                    }
                    if (state.messages.isEmpty) {
                      return Center(
                        child: _TelegramEmptyMessages(isDark: isDark),
                      );
                    }
                    final renderedMessages = _collapseMediaAlbums(
                      filteredMessages,
                    );

                    return Stack(
                      children: [
                        Scrollbar(
                          controller: _scrollController,
                          child: SelectionArea(
                            child: ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              cacheExtent: 500.0,
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                14,
                                20,
                                14,
                              ),
                              itemCount:
                                  renderedMessages.length +
                                  (state.hasMore || state.isLoadingMore
                                      ? 1
                                      : 0),
                              itemBuilder: (context, index) {
                                if (index >= renderedMessages.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 10, bottom: 10),
                                    child: Center(
                                      child: state.isLoadingMore
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: ButtonLoadingIndicator(),
                                            )
                                          : _TgOutlinedButton(
                                              label: 'تحميل الرسائل القديمة',
                                              isDark: isDark,
                                              onPressed: () => ref
                                                  .read(
                                                    conversationMessagesControllerProvider(
                                                      _conversationId,
                                                    ).notifier,
                                                  )
                                                  .loadMore(),
                                            ),
                                    ),
                                  );
                                }

                                final message = renderedMessages[index];
                                final older = index < renderedMessages.length - 1
                                    ? renderedMessages[index + 1]
                                    : null;
                                final senderId =
                                    message.sender?.id ?? message.senderId;
                                final olderSenderId =
                                    older?.sender?.id ?? older?.senderId;
                                final isMine = widget.currentUser?.id != null &&
                                    (senderId == widget.currentUser!.id ||
                                        message.sender?.id == widget.currentUser!.id);
                                final shouldBreakGroup =
                                    older == null ||
                                    olderSenderId != senderId ||
                                    message.createdAt
                                            .difference(older.createdAt)
                                            .inMinutes >
                                        6;

                                final newer = index > 0
                                    ? renderedMessages[index - 1]
                                    : null;
                                final newerSenderId =
                                    newer?.sender?.id ?? newer?.senderId;
                                final isLastInGroup =
                                    newer == null ||
                                    newerSenderId != senderId ||
                                    newer.createdAt
                                            .difference(message.createdAt)
                                            .inMinutes >
                                        6;

                                final senderName =
                                    message.sender?.displayName.isNotEmpty ==
                                        true
                                    ? message.sender!.displayName
                                    : (isMine ? 'أنت' : 'عضو');
                                final canEdit =
                                    senderId == widget.currentUser?.id &&
                                    !isReadOnly &&
                                    !message.hasAttachment &&
                                    !message.isDeleted;
                                final canDelete =
                                    !isReadOnly &&
                                    (senderId == widget.currentUser?.id ||
                                        widget.currentUser?.can(
                                              'canDeleteMessages',
                                            ) ==
                                            true);

                                final messageLocalDate =
                                    message.createdAt.toLocal();
                                final olderLocalDate =
                                    older?.createdAt.toLocal();
                                final showDate = olderLocalDate == null ||
                                    olderLocalDate.day !=
                                        messageLocalDate.day ||
                                    olderLocalDate.month !=
                                        messageLocalDate.month ||
                                    olderLocalDate.year !=
                                        messageLocalDate.year;

                                final stableItemKey =
                                    message.metadata?['clientMessageId']
                                        ?.toString() ??
                                    message.id;
                                final itemGlobalKey = _messageKeys.putIfAbsent(
                                  stableItemKey,
                                  GlobalKey.new,
                                );
                                _messageKeys[message.id] = itemGlobalKey;

                                return Padding(
                                  key: itemGlobalKey,
                                  padding: EdgeInsets.only(
                                    bottom: isLastInGroup ? 10 : 2,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (showDate)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Center(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? const Color(0xFF1E293B)
                                                    : Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isDark
                                                      ? const Color(0xFF334155)
                                                      : Colors.grey.shade300,
                                                ),
                                              ),
                                              child: Text(
                                                _formatDateDivider(
                                                  messageLocalDate,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      SwipeTo(
                                    onRightSwipe: (details) {
                                      if (_selectionMode) return;
                                      if (isReadOnly) return;
                                      setState(() {
                                        _replyingTo = message;
                                        _editingMessage = null;
                                      });
                                    },
                                    onLeftSwipe: (details) {
                                      if (_selectionMode) return;
                                      if (isReadOnly) return;
                                      setState(() {
                                        _replyingTo = message;
                                        _editingMessage = null;
                                      });
                                    },
                                    child: RepaintBoundary(
                                      child: MessageBubble(
                                        message: message,
                                      albumMessages: _albumFor(
                                        message,
                                        filteredMessages,
                                      ),
                                      onOpenAlbum: _showImagePreview,
                                      isMine: isMine,
                                      showAvatar: !isMine && isLastInGroup,
                                      showSenderName:
                                          liveConversation.type != 'direct' &&
                                          !isMine &&
                                          shouldBreakGroup,
                                      senderName: senderName,
                                      currentUserId:
                                          widget.currentUser?.id ?? '',
                                      avatarUrl: message.sender?.avatarUrl,
                                      token: widget.token,
                                      replyPreview: _replyPreviewFor(
                                        message,
                                        messageById,
                                      ),
                                      replyPreviewSender:
                                          _replyPreviewSenderFor(
                                            message,
                                            messageById,
                                          ),
                                      forwardedFrom: message.forwardedFromName,
                                      highlightQuery:
                                          _searchController.text.trim().isEmpty
                                          ? null
                                          : _searchController.text.trim(),
                                      selected: _selectedMessageIds.contains(
                                        message.id,
                                      ),
                                      selectionMode: _selectionMode,
                                      isActiveSearchMatch:
                                          activeSearchMessageId == message.id,
                                      chatPreferences: chatPreferences,
                                      onShowDetails:
                                          liveConversation.type != 'direct' &&
                                              isMine
                                          ? () => _showMessageDetails(message)
                                          : null,
                                      onTap: _selectionMode
                                          ? () => _toggleMessageSelection(
                                              message.id,
                                            )
                                          : null,
                                       onLongPress: () =>
                                           _toggleMessageSelection(message.id),
                                       onForward: () =>
                                           _forwardSingleMessage(message),
                                       onReply: () {
                                        if (_selectionMode) return;
                                        if (isReadOnly) return;
                                        setState(() {
                                          _replyingTo = message;
                                          _editingMessage = null;
                                        });
                                      },
                                      onCopy: () {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('تم نسخ الرسالة'),
                                          ),
                                        );
                                      },
                                      onEdit: canEdit
                                          ? () => setState(() {
                                              _editingMessage = message;
                                              _replyingTo = null;
                                              _messageController.text =
                                                  message.content;
                                            })
                                          : null,
                                      onDelete: (canDelete || message.isFailed) &&
                                          !message.isDeleted
                                          ? () => ref
                                                .read(
                                                  conversationMessagesControllerProvider(
                                                    _conversationId,
                                                  ).notifier,
                                                )
                                                .deleteMessage(message.id)
                                          : null,
                                      onOpenAttachment: () =>
                                          _openAttachment(message),
                                      onToggleFavorite: () => ref
                                          .read(
                                            conversationMessagesControllerProvider(
                                              _conversationId,
                                            ).notifier,
                                          )
                                          .toggleFavoriteMessage(
                                            messageId: message.id,
                                          ),
                                      onPin: canManagePinnedMessage
                                          ? () => ref
                                                .read(
                                                  chatOverviewControllerProvider
                                                      .notifier,
                                                )
                                                .setGroupPinnedMessage(
                                                  conversationId:
                                                      _conversationId,
                                                  content:
                                                      message.content.isNotEmpty
                                                      ? message.content
                                                      : (message.fileName ??
                                                            'Ù…Ø±Ù Ù‚'),
                                                  messageId: message.id,
                                                )
                                          : null,
                                      onVotePoll: (options) =>
                                          _votePoll(message.id, options),
                                      onExportPoll: () =>
                                          _exportPoll(message.id),
                                      onSaveAttachment:
                                          message.hasAttachment &&
                                              message.attachmentDownloadAllowed
                                          ? () => _downloadAttachment(
                                              message,
                                              forceSaveAs: true,
                                            )
                                          : null,
                                      onSaveSticker:
                                          (message.isStickerMessage ||
                                                  message.isImageMessage) &&
                                              message.attachmentDownloadAllowed
                                          ? () => _saveReceivedSticker(message)
                                          : null,
                                      onPrintAttachment:
                                          message.isPrintableAttachment
                                          ? () => _printAttachment(message)
                                          : null,
                                      onReact: (emoji) {
                                        if (isReadOnly) {
                                          return Future.value();
                                        }
                                        return ref
                                            .read(
                                              conversationMessagesControllerProvider(
                                                _conversationId,
                                              ).notifier,
                                            )
                                            .toggleReaction(
                                              messageId: message.id,
                                              emoji: emoji,
                                            );
                                      },
                                      onRetry: message.isFailed
                                          ? () => _retryMessage(message)
                                          : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                            ),
                          ),
                        ),
                        Positioned(
                          right: 18,
                          bottom: 18,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 180),
                            offset: _showScrollToBottomButton
                                ? Offset.zero
                                : const Offset(0, 1.5),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _showScrollToBottomButton ? 1 : 0,
                              child: IgnorePointer(
                                ignoring: !_showScrollToBottomButton,
                                child: Badge(
                                  isLabelVisible: _unreadBelowCount > 0,
                                  label: Text('$_unreadBelowCount'),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _scrollToBottom(),
                                      borderRadius: BorderRadius.circular(999),
                                      child: Ink(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF202B36)
                                              : Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: isDark ? 0.28 : 0.14,
                                              ),
                                              blurRadius: 18,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outlineVariant,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF1F2937),
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // ── Typing indicator ─────────────────────────────────────────
              SizedBox(
                height: 22,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _typingUsers.isEmpty
                      ? const SizedBox.shrink(key: ValueKey('no_typing'))
                      : Padding(
                          key: const ValueKey('typing'),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              _typingUsers.length == 1
                                  ? '${_typingUsers.first} يكتب...'
                                  : '${_typingUsers.length} أعضاء يكتبون...',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF3390EC),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                ),
              ),

              // ── Read-only banner ─────────────────────────────────────────
              if (isReadOnly)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF3A2800)
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _readOnlyBannerText(liveConversation),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFFFCD34D)
                                : const Color(0xFF9A3412),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Reply / edit banner ──────────────────────────────────────
              if (_replyingTo != null || _editingMessage != null)
                _ComposerBanner(
                  isEditing: _editingMessage != null,
                  text: _editingMessage != null
                      ? _editingMessage!.content
                      : (_replyingTo!.content.isNotEmpty
                            ? _replyingTo!.content
                            : (_replyingTo!.fileName ?? 'مرفق')),
                  isDark: isDark,
                  onClose: () => setState(() {
                    _replyingTo = null;
                    _editingMessage = null;
                  }),
                ),

              if (_isDownloadingAttachment)
                _DesktopDownloadBanner(
                  fileName: _downloadingFileName ?? 'مرفق',
                  progress: _downloadProgress,
                  isDark: isDark,
                ),

              if (_mentionQuery != null && _mentionResults.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _mentionResults.length,
                    itemBuilder: (context, index) {
                      final user = _mentionResults[index];
                      return ListTile(
                        dense: true,
                        leading: SafeNetworkAvatar(
                          imageUrl: user.avatarUrl,
                          fallbackText: user.displayName.isNotEmpty
                              ? user.displayName[0].toUpperCase()
                              : '?',
                          radius: 14,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                        ),
                        title: Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '@${user.username}',
                          maxLines: 1,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => _insertMention(user),
                      );
                    },
                  ),
                ),

              // ── Input ────────────────────────────────────────────────────
              ChatInput(
                controller: _messageController,
                focusNode: _messageFocusNode,
                isEditing: _editingMessage != null,
                isUploading: _isUploadingAttachment,
                uploadProgress: _uploadProgress,
                uploadLabel: _uploadingFileName,
                enterSendsMessage: enterSendsMessage,
                onChanged: (_) => _scheduleStopTyping(),
                onSend: _sendText,
                onSendOptions: _showSendOptions,
                onAttachFile: () => _sendFile(),
                onPickImage: _sendImage,
                onSendScreenshot: _sendScreenshotFromOpenWindow,
                onOpenReactionPicker: _showComposerReactionPicker,
                onSendPoll: _createPoll,
                onSendChecklist: _createChecklist,
                onSendGif: _openGifPicker,
                enabled: !isReadOnly,
              ),
            ],
          ),

          // ── Drag overlay ─────────────────────────────────────────────────
          if (_draggingFiles && !isReadOnly)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3390EC).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF3390EC),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.upload_file_rounded,
                          size: 48,
                          color: Color(0xFF3390EC),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'أفلت الملفات هنا للإرسال',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1C2B3A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Chat Header ────────────────────────────────────────────────────────────────
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.currentUserId,
    required this.statusText,
    required this.statusColor,
    required this.onToggleInfoPanel,
    required this.onCloseConversation,
    required this.rightPanelVisible,
    required this.onOpenSearch,
    required this.onOpenRemoteSearch,
    required this.onOpenGallery,
    required this.onOpenRemoteDesktop,
    required this.onProbePeerConnection,
    required this.hasRemotePeerDevice,
    this.remotePeerDevice,
    required this.isResolvingRemotePeer,
    required this.selectionMode,
    required this.onClearSelection,
    required this.onForwardSelected,
    required this.onShowScheduled,
    required this.isDark,
    required this.appearance,
  });

  final ChatConversation conversation;
  final String currentUserId;
  final String statusText;
  final Color statusColor;
  final VoidCallback onToggleInfoPanel;
  final VoidCallback onCloseConversation;
  final bool rightPanelVisible;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenRemoteSearch;
  final VoidCallback onOpenGallery;
  final VoidCallback onOpenRemoteDesktop;
  final VoidCallback onProbePeerConnection;
  final bool hasRemotePeerDevice;
  final BranchPeerDevice? remotePeerDevice;
  final bool isResolvingRemotePeer;
  final bool selectionMode;
  final VoidCallback onClearSelection;
  final VoidCallback onForwardSelected;
  final VoidCallback onShowScheduled;
  final bool isDark;
  final ChatResolvedAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final title = conversation.displayTitle(currentUserId);
    final peer = conversation.type == 'direct'
        ? conversation.members
              .where((m) => m.id != currentUserId)
              .cast<ChatDirectoryUser?>()
              .firstWhere((_) => true, orElse: () => null)
        : null;
    final headerTooltip = (peer?.jobTitle.trim().isNotEmpty == true)
        ? '$title\n💼 ${peer!.jobTitle.trim()}'
        : title;

    final headerBg = Color.lerp(
      appearance.incomingBubbleColor,
      isDark ? const Color(0xFF212121) : Colors.white,
      isDark ? 0.18 : 0.44,
    )!;
    final titleColor = isDark ? Colors.white : const Color(0xFF1C2B3A);
    final iconColor = isDark ? Colors.white60 : const Color(0xFF708499);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: headerBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Avatar ────────────────────────────────────────────────────────
          SafeNetworkAvatar(
            radius: 19,
            backgroundColor: conversationTypeAccent(
              conversation.type,
            ).withValues(alpha: 0.18),
            imageUrl: (conversation.type == 'direct' ? peer?.avatarUrl : conversation.avatarUrl) ?? conversation.avatarUrl ?? peer?.avatarUrl,
            fallbackIcon: conversationTypeIcon(conversation.type),
            fallbackIconSize: 18,
            fallbackIconColor: conversationTypeAccent(conversation.type),
          ),
          const SizedBox(width: 10),

          // ── Title + status ────────────────────────────────────────────────
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggleInfoPanel,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: headerTooltip,
                      waitDuration: const Duration(milliseconds: 250),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: titleColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      (peer?.jobTitle.trim().isNotEmpty == true)
                          ? '${peer!.jobTitle.trim()} • $statusText'
                          : statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Action icons ──────────────────────────────────────────────────
          if (!selectionMode && conversation.type == 'direct')
            _TgHeaderIcon(
              icon: isResolvingRemotePeer
                  ? Icons.sync_rounded
                  : Icons.computer_rounded,
              tooltip: hasRemotePeerDevice
                  ? 'فتح Remote Desktop (${remotePeerDevice?.localIp ?? ''})'
                  : 'فتح Remote Desktop (انقر للبحث عن IP)',
              color: hasRemotePeerDevice
                  ? iconColor
                  : iconColor.withValues(alpha: 0.65),
              onPressed: onOpenRemoteDesktop,
            ),
          if (!selectionMode && conversation.type == 'direct')
            _TgHeaderIcon(
              icon: Icons.terminal_rounded,
              tooltip: hasRemotePeerDevice
                  ? 'فحص الاتصال عبر Terminal (${remotePeerDevice?.localIp ?? ''})'
                  : 'فحص الاتصال (انقر للبحث عن IP)',
              color: hasRemotePeerDevice
                  ? iconColor
                  : iconColor.withValues(alpha: 0.65),
              onPressed: onProbePeerConnection,
            ),
          if (!selectionMode)
            _TgHeaderIcon(
              tooltip: 'مظهر المحادثات',
              icon: Icons.palette_outlined,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChatAppearanceScreen(),
                  ),
                );
              },
              color: iconColor,
            ),
          if (!selectionMode)
            _TgHeaderIcon(
              icon: Icons.schedule_rounded,
              tooltip: 'الرسائل المجدولة',
              color: iconColor,
              onPressed: onShowScheduled,
            ),
          _TgHeaderIcon(
            icon: selectionMode
                ? Icons.forward_to_inbox_rounded
                : Icons.search_rounded,
            tooltip: selectionMode ? 'إعادة توجيه المحدد' : 'بحث في المحادثة',
            color: selectionMode ? appearance.accent : iconColor,
            onPressed: selectionMode ? onForwardSelected : onOpenSearch,
          ),
          if (!selectionMode)
            _TgHeaderIcon(
              icon: Icons.perm_media_outlined,
              tooltip: 'فتح المعرض',
              color: iconColor,
              onPressed: onOpenGallery,
            ),
          if (!selectionMode)
            _TgHeaderIcon(
              icon: Icons.travel_explore_rounded,
              tooltip: 'بحث في كل الرسائل',
              color: iconColor,
              onPressed: onOpenRemoteSearch,
            ),
          _TgHeaderIcon(
            icon: selectionMode
                ? Icons.close_rounded
                : (rightPanelVisible
                      ? Icons.info_rounded
                      : Icons.info_outline_rounded),
            tooltip: selectionMode
                ? 'إلغاء التحديد'
                : (rightPanelVisible ? 'إخفاء المعلومات' : 'عرض المعلومات'),
            color: selectionMode
                ? const Color(0xFFE53935)
                : (rightPanelVisible ? appearance.accent : iconColor),
            onPressed: selectionMode ? onClearSelection : onToggleInfoPanel,
          ),
          _TgHeaderIcon(
            icon: Icons.close_rounded,
            tooltip: 'إغلاق المحادثة',
            color: iconColor,
            onPressed: onCloseConversation,
          ),
        ],
      ),
    );
  }
}

class _TgHeaderIcon extends StatelessWidget {
  const _TgHeaderIcon({
    required this.icon,
    required this.onPressed,
    required this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

// ── Search Bar ─────────────────────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.totalMatches,
    required this.activeMatchIndex,
    required this.isDark,
    required this.appearance,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
    required this.onOpenGlobalSearch,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int totalMatches;
  final int activeMatchIndex;
  final bool isDark;
  final ChatResolvedAppearance appearance;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;
  final VoidCallback onOpenGlobalSearch;

  @override
  Widget build(BuildContext context) {
    final background = Color.lerp(
      appearance.incomingBubbleColor,
      isDark ? const Color(0xFF1E2936) : Colors.white,
      isDark ? 0.20 : 0.44,
    )!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: background,
        border: Border(
          bottom: BorderSide(color: appearance.accent.withValues(alpha: 0.14)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: appearance.accent),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : const Color(0xFF1C2B3A),
              ),
              decoration: InputDecoration(
                hintText: 'البحث في الرسائل...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white38 : const Color(0xFFADB5BD),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (controller.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: appearance.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                totalMatches == 0
                    ? '0 نتيجة'
                    : '$activeMatchIndex / $totalMatches',
                style: TextStyle(
                  fontSize: 12,
                  color: appearance.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'بحث في كل الرسائل',
            onPressed: onOpenGlobalSearch,
            icon: const Icon(Icons.travel_explore_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'النتيجة السابقة',
            onPressed: onPrevious,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
          ),
          IconButton(
            tooltip: 'النتيجة التالية',
            onPressed: onNext,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: isDark ? Colors.white54 : const Color(0xFF708499),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Composer Banner (reply / edit) ─────────────────────────────────────────────
class _ComposerBanner extends StatelessWidget {
  const _ComposerBanner({
    required this.text,
    required this.isEditing,
    required this.isDark,
    required this.onClose,
  });

  final String text;
  final bool isEditing;
  final bool isDark;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accentColor = isEditing
        ? const Color(0xFF4DCC6E)
        : const Color(0xFF3390EC);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2936) : const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accentColor, width: 3)),
      ),
      child: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_rounded : Icons.reply_rounded,
            size: 16,
            color: accentColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing ? 'تعديل الرسالة' : 'رد على',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : const Color(0xFF708499),
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onClose,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: isDark ? Colors.white38 : const Color(0xFFADB5BD),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryCountChip extends StatelessWidget {
  const _GalleryCountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DesktopDownloadBanner extends StatelessWidget {
  const _DesktopDownloadBanner({
    required this.fileName,
    required this.progress,
    required this.isDark,
  });

  final String fileName;
  final double progress;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: AppDownloadProgressBanner(fileName: fileName, progress: progress),
    );
  }
}

class _DesktopOpenWindow {
  const _DesktopOpenWindow({
    required this.windowId,
    required this.title,
    required this.appName,
  });

  final int windowId;
  final String title;
  final String appName;
}

class _DesktopChatMessagesLoadingSkeleton extends StatelessWidget {
  const _DesktopChatMessagesLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      children: const [
        Align(
          alignment: Alignment.center,
          child: ShimmerSkeleton(width: 128, height: 22, borderRadius: 12),
        ),
        SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerSkeleton(width: 72, height: 12, borderRadius: 999),
        ),
        SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerSkeleton(width: 280, height: 92, borderRadius: 18),
        ),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ShimmerSkeleton(width: 240, height: 76, borderRadius: 18),
        ),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerSkeleton(width: 316, height: 82, borderRadius: 18),
        ),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ShimmerSkeleton(width: 210, height: 62, borderRadius: 18),
        ),
      ],
    );
  }
}

IconData _attachmentIcon(String type) => switch (type) {
  'image' => Icons.image_outlined,
  'pdf' => Icons.picture_as_pdf_outlined,
  'audio' => Icons.mic_rounded,
  _ => Icons.attach_file_rounded,
};

// ── Empty messages state ───────────────────────────────────────────────────────
class _TelegramEmptyMessages extends StatelessWidget {
  const _TelegramEmptyMessages({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          'لا توجد رسائل بعد.\nابدأ المحادثة الآن!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white60 : const Color(0xFF708499),
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

// ── Outlined button (Telegram style) ──────────────────────────────────────────
class _TgOutlinedButton extends StatelessWidget {
  const _TgOutlinedButton({
    required this.label,
    required this.isDark,
    required this.onPressed,
  });

  final String label;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(
            color: const Color(0xFF3390EC).withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF3390EC).withValues(alpha: 0.08),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3390EC),
          ),
        ),
      ),
    );
  }
}


class _FullscreenImageViewer extends StatefulWidget {
  const _FullscreenImageViewer({
    required this.images,
    required this.initialIndex,
    required this.onDownload,
  });
  final List<ChatMessage> images;
  final int initialIndex;
  final void Function(ChatMessage, BuildContext) onDownload;

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (_currentIndex > 0) {
          _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_currentIndex < widget.images.length - 1) {
          _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          _handleKeyEvent(event);
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              itemCount: widget.images.length,
              itemBuilder: (_, index) => Center(
                child: InteractiveViewer(
                  child: Hero(
                    tag: 'image_${widget.images[index].id}',
                    child: AuthenticatedAttachmentImage(
                      message: widget.images[index],
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              top: 18,
              start: 18,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            if (widget.images[_currentIndex].attachmentDownloadAllowed)
              PositionedDirectional(
                top: 18,
                end: 18,
                child: IconButton.filledTonal(
                  onPressed: () => widget.onDownload(widget.images[_currentIndex], context),
                  icon: const Icon(Icons.download_rounded),
                ),
              ),
            if (widget.images.length > 1)
               Positioned(
                 bottom: 24,
                 left: 0,
                 right: 0,
                 child: Center(
                   child: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                     decoration: BoxDecoration(
                       color: Colors.black54,
                       borderRadius: BorderRadius.circular(16)
                     ),
                     child: Text(
                       '${_currentIndex + 1} / ${widget.images.length}',
                       style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                     ),
                   )
                 ),
               ),
          ],
        ),
      ),
    );
  }
}