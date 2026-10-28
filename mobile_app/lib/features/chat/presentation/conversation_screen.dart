import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' hide RefreshCallback;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:swipe_to/swipe_to.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/media_url_resolver.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/permission_request_coordinator.dart';
import '../../../shared/services/remote_print_service.dart';
import '../../../shared/widgets/app_loading_placeholders.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../data/chat_draft_store.dart';
import '../data/chat_socket_service.dart';
import '../models/chat_models.dart';
import '../utils/chat_attachment_policy.dart';
import 'attachment_send_dialogs.dart';
import 'chat_appearance.dart';
import 'chat_appearance_screen.dart';
import 'conversation_details_screen.dart';
import 'group_management_screen.dart';
import 'widgets/broadcast_target_picker_sheet.dart';
import 'widgets/attachment_bottom_sheet.dart';
import 'widgets/chat_audio_attachment_player.dart';
import 'widgets/chat_avatar.dart';
import 'widgets/chat_forward_sheet.dart';
import 'widgets/chat_link_text.dart';
import 'widgets/chat_poll_bubble.dart';
import 'widgets/chat_text_field_paste_menu.dart';
import 'widgets/gif_picker_panel.dart';
import 'widgets/poll_creator_dialog.dart';
import 'widgets/scheduled_messages_list.dart';
import 'widgets/whatsapp_reaction_picker.dart';
import 'widgets/chat_remote_search_sheet.dart';

/// خطوط احتياطية لعرض الإيموجي ملوّنًا (مهم على سطح المكتب/لينكس).
const List<String> _kChatReactionEmojiFontFallbacks = <String>[
  'Noto Color Emoji',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Segoe UI Symbol',
];

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversation,
    this.initialTargetMessage,
    this.initialMessageId,
  });

  final ChatConversation conversation;
  final ChatMessage? initialTargetMessage;
  final String? initialMessageId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _PrinterSelectionResult {
  const _PrinterSelectionResult({
    required this.confirmed,
    required this.printerName,
  });

  final bool confirmed;
  final String? printerName;
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  static const _draftStore = ChatDraftStore();
  bool _restoringDraft = false;
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  final Set<String> _selectedMessageIds = <String>{};
  final Set<String> _printingItemIds = <String>{};
  final Map<String, String> _itemIdToClientRequestId = <String, String>{};
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final AudioRecorder _audioRecorder = AudioRecorder();

  /// نخزن الـ typing users بالـ id عشان مانتلخبطش لو فيه أسماء مكررة
  final Map<String, String> _typingUsers = <String, String>{};

  StreamSubscription<ChatSocketEvent>? _subscription;

  ChatConversation? _conversation;
  ChatMessage? _replyingTo;
  bool _isSendingText = false;
  ChatMessage? _editingMessage;

  late final ProviderContainer _container;

  int _lastMessageCount = 0;
  bool _isLoadingMore = false;
  bool _showScrollToLatestButton = false;
  int _unreadBelowCount = 0;
  DateTime? _lastLoadMoreAt;
  bool _didSendTyping = false;
  String? _focusedMessageId;
  String? _pulsingHeartMessageId;
  bool _isUploadingAttachment = false;
  double _uploadProgress = 0;
  String? _uploadingFileName;

  // Per-message download state: messageId -> {progress: double, fileName: String}
  final Map<String, _MessageDownloadState> _downloadStates = {};
  final Set<String> _cachedAttachmentIds = <String>{};
  final Set<String> _checkedAttachmentIds = <String>{};

  void _syncCachedAttachments(List<ChatMessage> messages) {
    final repository = ref.read(chatRepositoryProvider);
    for (final message in messages) {
      if (!message.hasAttachment || _checkedAttachmentIds.contains(message.id)) {
        continue;
      }
      _checkedAttachmentIds.add(message.id);
      repository.isAttachmentCached(message).then((isCached) {
        if (isCached && mounted && !_cachedAttachmentIds.contains(message.id)) {
          setState(() {
            _cachedAttachmentIds.add(message.id);
          });
        }
      }).catchError((_) {});
    }
  }

  void _checkSingleAttachmentCached(ChatMessage message) {
    if (!message.hasAttachment || _checkedAttachmentIds.contains(message.id)) {
      return;
    }
    _checkedAttachmentIds.add(message.id);
    ref.read(chatRepositoryProvider).isAttachmentCached(message).then((isCached) {
      if (isCached && mounted && !_cachedAttachmentIds.contains(message.id)) {
        setState(() {
          _cachedAttachmentIds.add(message.id);
        });
      }
    }).catchError((_) {});
  }

  bool get _isDownloadingAttachment => _downloadStates.isNotEmpty;
  double get _downloadProgress =>
      _downloadStates.isEmpty ? 0 : _downloadStates.values.first.progress;
  String? get _downloadingFileName =>
      _downloadStates.isEmpty ? null : _downloadStates.values.first.fileName;
  bool _broadcastSendToAllDepartments = true;
  Set<String> _broadcastTargetDepartmentIds = <String>{};
  Set<String> _broadcastTargetUserIds = <String>{};
  bool _isRecordingVoice = false;
  bool _isVoiceRecordingPaused = false;
  Duration _recordingDuration = Duration.zero;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;
  String? _voiceDraftPath;
  int? _voiceDraftDurationMs;

  /// تيليجرام: ضغط مطوّل + سحب للإلغاء / للأعلى للقفل
  bool _isVoiceHoldActive = false;
  bool _isVoiceRecordingLocked = false;
  bool _voiceSlideCancelArmed = false;
  bool _voiceCaptureAborted = false;
  Offset _voiceGestureOffset = Offset.zero;
  final Set<String> _animatedMessageIds = <String>{};

  String? _mentionQuery;
  List<ChatDirectoryUser> _mentionResults = [];

  ChatConversation get _data => _conversation ?? widget.conversation;
  bool get _selectionMode => _selectedMessageIds.isNotEmpty;

  bool _isBlockedFromSending(String? userId) {
    if (userId == null || userId.isEmpty) {
      return false;
    }
    return _data.blockedMemberIds.any((entry) => entry == userId);
  }

  bool _isReadOnlyFor(String? userId) {
    return !_data.isActive ||
        _isBlockedFromSending(userId) ||
        !_canPublishInBroadcast(userId);
  }

  String _readOnlyTextFor(String? userId) {
    if (_isBlockedFromSending(userId)) {
      return 'تم تقييدك في هذه المحادثة. يمكنك قراءة الرسائل فقط.';
    }
    if (_data.type == 'broadcast' && !_canPublishInBroadcast(userId)) {
      return 'هذه قناة بث. ليس لديك صلاحية الإرسال فيها.';
    }
    return 'الغرفة معطلة بواسطة المشرف. المحادثة للقراءة فقط.';
  }

  bool _canPublishInBroadcast(String? userId) {
    if (_data.type != 'broadcast') {
      return true;
    }
    if (userId == null || userId.isEmpty) {
      return false;
    }
    if (_data.createdBy == userId) {
      return true;
    }
    if (_data.admins.any((entry) => entry.id == userId)) {
      return true;
    }
    return _data.broadcastPublisherIds.contains(userId);
  }

  bool _canManagePinnedMessage(String? userId) {
    if (_data.type != 'group') {
      return false;
    }
    if (userId == null || userId.isEmpty) {
      return false;
    }
    return _data.createdBy == userId;
  }

  Future<void> _upsertPinnedMessage({required bool edit}) async {
    final currentText = _data.pinnedMessage?.content ?? '';
    final controller = TextEditingController(text: edit ? currentText : '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(edit ? 'تعديل الرسالة المثبتة' : 'إضافة رسالة مثبتة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'اكتب الرسالة التي ستظهر أعلى المحادثة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (!mounted || value == null || value.isEmpty) {
      return;
    }

    final updated = await ref
        .read(chatOverviewControllerProvider.notifier)
        .setGroupPinnedMessage(conversationId: _data.id, content: value);
    if (!mounted) {
      return;
    }
    setState(() => _conversation = updated);
  }

  Future<void> _clearPinnedMessage() async {
    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف الرسالة المثبتة'),
            content: const Text('هل تريد حذف الرسالة المثبتة الحالية؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) {
      return;
    }

    final updated = await ref
        .read(chatOverviewControllerProvider.notifier)
        .clearGroupPinnedMessage(conversationId: _data.id);
    if (!mounted) {
      return;
    }
    setState(() => _conversation = updated);
  }

  @override
  void initState() {
    super.initState();

    _container = ProviderScope.containerOf(context, listen: false);
    _conversation = widget.conversation;

    if (widget.initialTargetMessage != null) {
      _focusedMessageId = widget.initialTargetMessage!.id;
    } else if (widget.initialMessageId != null) {
      _focusedMessageId = widget.initialMessageId;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _container.read(activeConversationIdProvider.notifier).state =
          widget.conversation.id;
      _container.read(chatSocketServiceProvider).markActivity();
      final controller = ref.read(
        conversationMessagesControllerProvider(
          widget.conversation.id,
        ).notifier,
      );
      controller.markSeen();
      controller.refresh();

      final target = widget.initialTargetMessage;
      final targetId = target?.id ?? widget.initialMessageId;
      if (targetId != null) {
        if (target != null) {
          await ref
              .read(
                conversationMessagesControllerProvider(
                  widget.conversation.id,
                ).notifier,
              )
              .hydrateMessages([target]);
        }
        if (!mounted) return;
        await Future<void>.delayed(const Duration(milliseconds: 160));
        if (!mounted) return;
        await _scrollToMessageById(targetId);

        Future<void>.delayed(const Duration(milliseconds: 2800), () {
          if (!mounted) return;
          if (_focusedMessageId == targetId) {
            setState(() {
              _focusedMessageId = null;
            });
          }
        });
      }
    });

    _scrollController.addListener(_onScroll);
    _messageController.addListener(_onMessageDraftChanged);
    unawaited(_restoreDraft());

    _subscription = ref.read(chatSocketServiceProvider).events.listen((event) {
      if (!mounted) {
        return;
      }

      if (event.type == 'presence_updated' ||
          event.type == 'user_online' ||
          event.type == 'user_offline') {
        final userId = event.payload['userId']?.toString();
        if (userId == null || userId.isEmpty) {
          return;
        }
        final members = _data.members
            .map(
              (member) => member.id == userId
                  ? ChatDirectoryUser(
                      id: member.id,
                      username: member.username,
                      fullName: member.fullName,
                      role: member.role,
                      departmentId: member.departmentId,
                      branchId: member.branchId,
                      branchCode: member.branchCode,
                      isOnline:
                          event.payload['isOnline'] as bool? ??
                          event.type == 'user_online',
                      presenceStatus:
                          event.payload['presenceStatus']?.toString() ??
                          ((event.payload['isOnline'] as bool? ??
                                  event.type == 'user_online')
                              ? 'online'
                              : 'offline'),
                      isActive: member.isActive,
                      avatarUrl: member.avatarUrl,
                      lastSeen: event.payload['lastSeen'] is String
                          ? DateTime.tryParse(
                              event.payload['lastSeen'] as String,
                            )
                          : member.lastSeen,
                      lastActiveAt: event.payload['lastActiveAt'] is String
                          ? DateTime.tryParse(
                              event.payload['lastActiveAt'] as String,
                            )
                          : member.lastActiveAt,
                    )
                  : member,
            )
            .toList();
        setState(() {
          _conversation = _data.copyWith(members: members);
        });
        return;
      }

      if (event.payload['conversationId']?.toString() != widget.conversation.id) {
        return;
      }

      if (event.type == 'receive_message') {
        final incomingMessage = ChatMessage.fromJson(event.payload);
        final senderId = incomingMessage.sender?.id;
        if (senderId != null && senderId.isNotEmpty) {
          setState(() {
            _typingUsers.remove(senderId);
          });
        }
        final isChatVisible = _container.read(chatAppVisibilityProvider);
        final activeConversationId = _container.read(
          activeConversationIdProvider,
        );
        if (isChatVisible && activeConversationId == widget.conversation.id) {
          unawaited(
            ref
                .read(
                  conversationMessagesControllerProvider(
                    widget.conversation.id,
                  ).notifier,
                )
                .markSeen(),
          );
        }
        return;
      }

      if (event.type == 'conversation_deleted') {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
        return;
      }

      if (event.type == 'conversation_state_changed' &&
          event.payload['conversationId']?.toString() ==
              widget.conversation.id) {
        final nextActive = event.payload['isActive'] == true;
        setState(() {
          _conversation = _data.copyWith(isActive: nextActive);
        });
        return;
      }

      if (event.type == 'typing') {
        final typingUserId = _extractTypingUserId(event.payload);
        final typingUserName = _extractTypingUserName(event.payload);
        final currentUserId = ref.read(authControllerProvider).valueOrNull?.id;

        if (typingUserId != null &&
            typingUserName != null &&
            typingUserId != currentUserId) {
          setState(() {
            _typingUsers[typingUserId] = typingUserName;
          });
        }
      } else if (event.type == 'stop_typing') {
        final typingUserId = _extractTypingUserId(event.payload);
        final currentUserId = ref.read(authControllerProvider).valueOrNull?.id;

        if (typingUserId != null && typingUserId != currentUserId) {
          setState(() {
            _typingUsers.remove(typingUserId);
          });
        }
      } else if (event.type == 'conversation_updated' &&
          event.payload['id']?.toString() == widget.conversation.id) {
        setState(() {
          _conversation = ChatConversation.fromJson(event.payload);
        });
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final isNear = _isNearBottom();
    final shouldShowScrollToLatest = !isNear;
    if (isNear && _unreadBelowCount > 0 && mounted) {
      setState(() {
        _unreadBelowCount = 0;
      });
    }
    if (shouldShowScrollToLatest != _showScrollToLatestButton) {
      setState(() {
        _showScrollToLatestButton = shouldShowScrollToLatest;
      });
    }

    if (_isLoadingMore) return;

    final messagesData = ref
        .read(conversationMessagesControllerProvider(widget.conversation.id))
        .valueOrNull;
    final canLoadMore =
        (messagesData?.hasMore ?? false) &&
        !(messagesData?.isLoadingMore ?? false);
    if (!canLoadMore) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      final now = DateTime.now();
      if (_lastLoadMoreAt != null &&
          now.difference(_lastLoadMoreAt!) <
              const Duration(milliseconds: 450)) {
        return;
      }
      _lastLoadMoreAt = now;
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_scrollController.hasClients) return;

    _isLoadingMore = true;
    try {
      await ref
          .read(
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
          )
          .loadMore();
    } finally {
      _isLoadingMore = false;
    }
  }

  void _clearActiveConversationSelection() {
    _container.read(activeConversationIdProvider.notifier).state = null;
  }

  static const int _chatMaxUploadBytesUser = 20 * 1024 * 1024;
  static const int _chatMaxUploadBytesAdmin = 200 * 1024 * 1024;

  int _maxChatAttachmentBytes() {
    final user = ref.read(authControllerProvider).valueOrNull;
    final customLimitMB = user?.maxAttachmentSizeMB;
    final defaultLimit = user?.role == 'admin'
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

  @override
  void dispose() {
    // Do not leave a stale active conversation behind after navigating back.
    // The overview controller uses this value to decide whether an incoming
    // message should increment the unread badge.
    final activeConversationId = _container.read(activeConversationIdProvider);
    if (activeConversationId == widget.conversation.id) {
      _clearActiveConversationSelection();
    }
    _messageController.removeListener(_onMessageTextChanged);
    _messageController.removeListener(_onMessageDraftChanged);
    _scrollController.removeListener(_onScroll);
    _recordingTicker?.cancel();
    _audioRecorder.dispose();
    _subscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final draft = await _draftStore.load(widget.conversation.id);
    if (!mounted || draft == null || draft.isEmpty) return;
    _restoringDraft = true;
    _messageController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _restoringDraft = false;
  }

  void _onMessageDraftChanged() {
    if (_restoringDraft) return;
    unawaited(
      _draftStore.save(widget.conversation.id, _messageController.text),
    );
  }

  void _onMessageTextChanged() {
    if (_data.type != 'group' && _data.type != 'department') return;
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
    final allMembers = _data.members;
    final filtered = allMembers.where((m) {
      return m.displayName.toLowerCase().contains(lowerQuery) ||
          m.username.toLowerCase().contains(lowerQuery);
    }).toList();

    setState(() {
      _mentionQuery = query;
      _mentionResults = filtered;
    });
  }

  Future<void> _sendSpecificFile(String path) async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }
    final sendDraft = await showAttachmentSendDialog(context, path);
    if (sendDraft == null) return;
    await _sendPreparedFile(
      sendPath: sendDraft.filePath,
      displayName: sendDraft.displayName,
      restrictForwardAndDownload: sendDraft.restrictForwardAndDownload,
      caption: sendDraft.caption,
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

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
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
                title: const Text('إرسال بدون صوت', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: const Text('يصل إشعار صامت للمستلم دون إصدار نغمة', style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendText(isSilent: true);
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
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
              ListTile(
                dense: true,
                leading: const Icon(Icons.timer_outlined, size: 20, color: Color(0xFF007AFF)),
                title: const Text('بعد 30 دقيقة', style: TextStyle(fontSize: 14)),
                trailing: Text(
                  DateFormat('hh:mm a', 'ar').format(now.add(const Duration(minutes: 30))),
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendText(scheduledFor: now.add(const Duration(minutes: 30)));
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.timer_outlined, size: 20, color: Color(0xFF007AFF)),
                title: const Text('بعد ساعة واحدة', style: TextStyle(fontSize: 14)),
                trailing: Text(
                  DateFormat('hh:mm a', 'ar').format(now.add(const Duration(hours: 1))),
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendText(scheduledFor: now.add(const Duration(hours: 1)));
                },
              ),
              if (now.isBefore(today6PM.subtract(const Duration(minutes: 30))))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.nightlight_round, size: 20, color: Color(0xFF007AFF)),
                  title: const Text('مساء اليوم (06:00 م)', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _sendText(scheduledFor: today6PM);
                  },
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.wb_sunny_rounded, size: 20, color: Color(0xFF007AFF)),
                title: const Text('صباح الغد (09:00 ص)', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendText(scheduledFor: tomorrow9AM);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.edit_calendar_rounded, size: 20, color: Color(0xFF007AFF)),
                title: const Text('تحديد موعد مخصص...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(sheetContext);
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
        );
      },
    );
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

    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  void _scheduleStopTyping() {
    final notifier = ref.read(
      conversationMessagesControllerProvider(widget.conversation.id).notifier,
    );

    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText) {
      if (!_didSendTyping) {
        notifier.sendTyping();
        _didSendTyping = true;
      }
      return;
    }
    if (_didSendTyping) {
      notifier.stopTyping();
      _didSendTyping = false;
    }
  }

  List<String> _extractMentions(String text) {
    if (_data.type != 'group' && _data.type != 'department') return const [];
    final mentions = <String>[];
    final regex = RegExp(r'@([A-Za-z0-9_]+)');
    for (final match in regex.allMatches(text)) {
      final username = match.group(1);
      if (username == null) continue;
      if (username.toLowerCase() == 'all') {
        mentions.addAll(_data.members.map((m) => m.id));
        continue;
      }
      try {
        final user = _data.members.firstWhere(
          (m) => m.username.toLowerCase() == username.toLowerCase(),
        );
        mentions.add(user.id);
      } catch (_) {}
    }
    return mentions.toSet().toList(); // Ensure unique mentions
  }

  Future<void> _sendText({
    bool isSilent = false,
    DateTime? scheduledFor,
  }) async {
    if (_isSendingText) return;

    if (_isUploadingAttachment) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('انتظر حتى يكتمل رفع الملف الحالي أولًا.'),
        ),
      );
      return;
    }

    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final broadcastMetadata = await _pickBroadcastTargetsMetadata();
    if (_data.type == 'broadcast' && broadcastMetadata == null) {
      return;
    }

    final payloadMetadata = <String, dynamic>{
      ...?_replyMetadata(_replyingTo),
      ...?broadcastMetadata,
      if (_extractMentions(text).isNotEmpty) 'mentions': _extractMentions(text),
    };

    final notifier = ref.read(
      conversationMessagesControllerProvider(widget.conversation.id).notifier,
    );

    _isSendingText = true;
    final wasEditing = _editingMessage != null;
    final targetEditingMessage = _editingMessage;
    final targetReplyingTo = _replyingTo;

    // Immediately clear text field and draft for instant UI response and prevent double sends
    _messageController.clear();
    unawaited(_draftStore.clear(widget.conversation.id));

    if (mounted) {
      setState(() {
        _replyingTo = null;
        _editingMessage = null;
        if (authUserId != null && authUserId.isNotEmpty) {
          _typingUsers.remove(authUserId);
        }
      });
      _scrollToBottom(animated: true);
    }

    notifier.stopTyping();
    _didSendTyping = false;

    try {
      if (wasEditing && targetEditingMessage != null) {
        await notifier.editMessage(messageId: targetEditingMessage.id, content: text);
      } else {
        await notifier.sendText(
          text,
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

  Future<void> _sendFile() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) {
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
      final path = paths.first;
      final file = File(path);
      final fileSize = await file.length();
      if (fileSize > _maxChatAttachmentBytes()) {
        if (!mounted) {
          return;
        }
        _showChatAttachmentSizeExceededSnackbar();
        return;
      }
      if (!mounted) {
        return;
      }
      final sendDraft = await showAttachmentSendDialog(context, path);
      if (sendDraft == null) {
        return;
      }
      await _sendPreparedFile(
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
    if (_data.type == 'broadcast') {
      fixedBroadcastMetadata = await _pickBroadcastTargetsMetadata();
      if (fixedBroadcastMetadata == null) {
        return;
      }
    }

    int sentCount = 0;
    int skippedCount = 0;
    final mediaGroupId = 'album_${DateTime.now().microsecondsSinceEpoch}';
    for (final path in paths) {
      final file = File(path);
      final fileSize = await file.length();
      if (fileSize > _maxChatAttachmentBytes()) {
        skippedCount++;
        continue;
      }
      await _sendPreparedFile(
        sendPath: path,
        displayName: p.basename(path),
        restrictForwardAndDownload: restrictForwardAndDownload,
        fixedBroadcastMetadata: fixedBroadcastMetadata,
        extraMetadata: {
          'mediaGroupId': mediaGroupId,
          'mediaGroupSize': paths.length,
        },
      );
      sentCount++;
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

  Future<void> _sendImages() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }

    final List<XFile> images = await ImagePicker().pickMultiImage(
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (images.isEmpty) {
      return;
    }
    final paths = images
        .map((img) => img.path)
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
    if (_data.type == 'broadcast') {
      fixedBroadcastMetadata = await _pickBroadcastTargetsMetadata();
      if (fixedBroadcastMetadata == null) {
        return;
      }
    }

    int sentCount = 0;
    int skippedCount = 0;
    for (final path in paths) {
      final file = File(path);
      final fileSize = await file.length();
      if (fileSize > _maxChatAttachmentBytes()) {
        skippedCount++;
        continue;
      }
      await _sendPreparedFile(
        sendPath: path,
        displayName: p.basename(path),
        restrictForwardAndDownload: restrictForwardAndDownload,
        fixedBroadcastMetadata: fixedBroadcastMetadata,
      );
      sentCount++;
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

  Future<void> _takePhotoAndSend() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }
    if (_isUploadingAttachment) return;

    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (photo == null || !mounted) return;

    final file = File(photo.path);
    if (await file.length() > _maxChatAttachmentBytes()) {
      if (mounted) _showChatAttachmentSizeExceededSnackbar();
      return;
    }
    if (!mounted) return;

    final sendDraft = await showAttachmentSendDialog(context, photo.path);
    if (sendDraft == null) return;

    await _sendPreparedFile(
      sendPath: sendDraft.filePath,
      displayName: sendDraft.displayName,
      restrictForwardAndDownload: sendDraft.restrictForwardAndDownload,
      caption: sendDraft.caption,
    );
  }

  Future<void> _createPoll() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) return;

    final pollData = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
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
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) return;

    final pollData = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
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

  Future<void> _openEmojiPicker() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) return;

    final emoji = await WhatsAppReactionPickerSheet.show(context);
    if (emoji != null && emoji.isNotEmpty && mounted) {
      final text = _messageController.text;
      final selection = _messageController.selection;
      final start = selection.start >= 0 ? selection.start : text.length;
      final end = selection.end >= 0 ? selection.end : text.length;
      final newText = text.replaceRange(start, end, emoji);
      _messageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + emoji.length),
      );
    }
  }

  Future<void> _openGifPicker() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) return;

    final sticker = await showModalBottomSheet<LocalSticker>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const GifPickerPanel(),
    );

    if (sticker != null && mounted) {
      final ext = resolveStickerExtension(sticker.bytes, sticker.name);
      final safeBaseName = p.basenameWithoutExtension(sticker.name);
      final finalName = '$safeBaseName$ext';
      final stickerFile = File(
        p.join(
          Directory.systemTemp.path,
          'sticker_${sticker.id}_$finalName',
        ),
      );
      await stickerFile.writeAsBytes(sticker.bytes, flush: true);
      await _sendPreparedFile(
        sendPath: stickerFile.path,
        displayName: finalName,
        restrictForwardAndDownload: false,
        extraMetadata: const {'sticker': true},
      );
    }
  }

  Future<void> _sendScreenshotFromDevice() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }

    final messagesState = ref.read(
      conversationMessagesControllerProvider(widget.conversation.id),
    );
    final hasProtectedAttachment =
        messagesState.valueOrNull?.messages.any(
          (message) =>
              message.hasAttachment && !message.attachmentDownloadAllowed,
        ) ??
        false;
    if (hasProtectedAttachment) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تعطيل التقاط الشاشة داخل هذه المحادثة لوجود مرفقات محمية.',
          ),
        ),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.image,
      dialogTitle: 'اختر لقطة الشاشة',
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final screenshotPath = result.files.first.path;
    if (screenshotPath == null || screenshotPath.isEmpty) {
      return;
    }

    final extension = p.extension(screenshotPath).toLowerCase();
    final fileName =
        'screenshot_${DateTime.now().millisecondsSinceEpoch}${extension.isEmpty ? '.png' : extension}';

    await _sendPreparedFile(
      sendPath: screenshotPath,
      displayName: fileName,
      restrictForwardAndDownload: false,
    );
  }

  Future<void> _showComposerReactionPicker() async {
    final messages =
        ref
            .read(
              conversationMessagesControllerProvider(widget.conversation.id),
            )
            .valueOrNull
            ?.messages ??
        const <ChatMessage>[];

    ChatMessage? target = _replyingTo;
    if (target == null) {
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

    await _showFullReactionPicker(target);
  }

  Future<void> _sendPreparedFile({
    required String sendPath,
    required String displayName,
    required bool restrictForwardAndDownload,
    String? caption,
    Map<String, dynamic>? extraMetadata,
    Map<String, dynamic>? fixedBroadcastMetadata,
  }) async {
    if (isChatAttachmentExtensionBlocked(sendPath)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kChatBlockedAttachmentUserMessage)),
      );
      return;
    }

    final sendFile = File(sendPath);
    final sendFileSize = await sendFile.length();
    if (sendFileSize > _maxChatAttachmentBytes()) {
      if (!mounted) {
        return;
      }
      _showChatAttachmentSizeExceededSnackbar();
      return;
    }

    final broadcastMetadata =
        fixedBroadcastMetadata ?? await _pickBroadcastTargetsMetadata();
    if (_data.type == 'broadcast' && broadcastMetadata == null) {
      return;
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
    };

    setState(() {
      _isUploadingAttachment = true;
      _uploadProgress = 0;
      _uploadingFileName = displayName;
    });

    try {
      await ref
          .read(
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
          )
          .sendFile(
            sendPath,
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
        return;
      }
      setState(() {
        _replyingTo = null;
        _editingMessage = null;
      });

      _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messageFromChatDioError(e))));
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
    final imagePaths = paths
        .where((path) {
          final ext = p.extension(path).toLowerCase();
          return ext == '.png' ||
              ext == '.jpg' ||
              ext == '.jpeg' ||
              ext == '.webp' ||
              ext == '.gif';
        })
        .take(6)
        .toList();

    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final dialogWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
            280.0,
            420.0,
          );
          final dialogHeight = MediaQuery.sizeOf(context).height * 0.76;

          return AlertDialog(
            title: Text('إرسال ${paths.length} ملفات'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dialogWidth.toDouble(),
                maxHeight: dialogHeight,
              ),
              child: SizedBox(
                width: dialogWidth.toDouble(),
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
                                    width: 64,
                                    height: 64,
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
                          .take(8)
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
                      if (paths.length > 8)
                        Text('... و ${paths.length - 8} ملف إضافي'),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: restrictForwardAndDownload,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('🔒 محتوى محمي (لهذه الملفات فقط)'),
                        subtitle: const Text('منع إعادة التوجيه والتحميل للملفات المحددة فقط دون التأثير على المحادثة'),
                        onChanged: (value) => setDialogState(() {
                          restrictForwardAndDownload = value == true;
                        }),
                      ),
                    ],
                  ),
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
          );
        },
      ),
    );
  }

  Future<void> _startVoiceRecording() async {
    if (_isUploadingAttachment) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('انتظر حتى يكتمل رفع الملف الحالي أولًا.'),
        ),
      );
      return;
    }

    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }

    final hasPermission = await PermissionRequestCoordinator.run(
      _audioRecorder.hasPermission,
    );
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مطلوب إذن الميكروفون لتسجيل الملاحظة الصوتية.'),
        ),
      );
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final outputPath = p.join(tempDir.path, fileName);

    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: outputPath,
    );

    if (!mounted) {
      return;
    }
    if (_voiceCaptureAborted) {
      final abandoned = await _audioRecorder.stop();
      if (abandoned != null && abandoned.isNotEmpty) {
        try {
          final f = File(abandoned);
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoice = false;
        _isVoiceRecordingPaused = false;
        _recordingDuration = Duration.zero;
        _recordingStartedAt = null;
        _voiceCaptureAborted = false;
      });
      return;
    }
    setState(() {
      _isRecordingVoice = true;
      _recordingDuration = Duration.zero;
      _recordingStartedAt = DateTime.now();
    });

    _recordingTicker?.cancel();
    _recordingTicker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final started = _recordingStartedAt;
      if (!_isRecordingVoice || started == null) return;
      setState(() {
        _recordingDuration = DateTime.now().difference(started);
      });
    });
  }

  Future<void> _handleVoiceMicLongPressStart() async {
    if (_isUploadingAttachment ||
        _isRecordingVoice ||
        _voiceDraftPath != null) {
      return;
    }
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      return;
    }
    _voiceCaptureAborted = false;
    setState(() {
      _isVoiceHoldActive = true;
      _voiceSlideCancelArmed = false;
      _voiceGestureOffset = Offset.zero;
      _isVoiceRecordingLocked = false;
    });
    HapticFeedback.mediumImpact();
    await _startVoiceRecording();
    if (!mounted) {
      return;
    }
    if (!_isRecordingVoice) {
      setState(() {
        _isVoiceHoldActive = false;
        _voiceGestureOffset = Offset.zero;
      });
    }
  }

  void _handleVoiceMicLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_isRecordingVoice) {
      return;
    }
    final o = details.offsetFromOrigin;
    // Natural horizontal swipe in either direction (left or right) to cancel
    final cancel = o.dx.abs() > 36;
    // Sliding up by 50px locks hands-free recording
    final lock = o.dy < -50;

    if (cancel && !_voiceSlideCancelArmed) {
      HapticFeedback.selectionClick();
    }

    setState(() {
      _voiceGestureOffset = o;
      _voiceSlideCancelArmed = cancel;
      if (lock && !_isVoiceRecordingLocked) {
        _isVoiceRecordingLocked = true;
        _isVoiceHoldActive = false;
        HapticFeedback.heavyImpact();
      }
    });
  }

  Future<void> _handleVoiceMicLongPressEnd() async {
    if (!_isRecordingVoice) {
      _voiceCaptureAborted = true;
      if (mounted) {
        setState(() {
          _isVoiceHoldActive = false;
          _voiceSlideCancelArmed = false;
          _voiceGestureOffset = Offset.zero;
        });
      }
      return;
    }

    if (_voiceSlideCancelArmed) {
      setState(() {
        _isVoiceHoldActive = false;
        _isVoiceRecordingLocked = false;
        _voiceSlideCancelArmed = false;
        _voiceGestureOffset = Offset.zero;
      });
      await _cancelVoiceRecording();
      return;
    }

    if (_isVoiceRecordingLocked) {
      setState(() {
        _isVoiceHoldActive = false;
        _voiceSlideCancelArmed = false;
        _voiceGestureOffset = Offset.zero;
      });
      return;
    }

    // Accidental tap protection (< 550ms)
    final started = _recordingStartedAt;
    final dur = started == null
        ? _recordingDuration
        : DateTime.now().difference(started);
    if (dur.inMilliseconds < 550) {
      await _cancelVoiceRecording();
      return;
    }

    setState(() {
      _isVoiceHoldActive = false;
      _voiceSlideCancelArmed = false;
      _voiceGestureOffset = Offset.zero;
    });
    await _stopAndSendVoiceNote();
  }

  Future<void> _stopAndSendVoiceNote() => _finishVoiceRecording(sendNote: true);

  Future<void> _cancelVoiceRecording() =>
      _finishVoiceRecording(sendNote: false);

  Future<void> _sendVoiceDraft() async {
    final path = _voiceDraftPath;
    final durationMs = _voiceDraftDurationMs;
    if (path == null || path.isEmpty || durationMs == null) {
      return;
    }
    await _sendPreparedFile(
      sendPath: path,
      displayName: 'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a',
      restrictForwardAndDownload: false,
      extraMetadata: <String, dynamic>{
        'voiceNote': true,
        'durationMs': durationMs,
      },
    );
    if (!mounted) return;
    setState(() {
      _voiceDraftPath = null;
      _voiceDraftDurationMs = null;
    });
  }

  Future<void> _deleteVoiceDraft() async {
    final path = _voiceDraftPath;
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _voiceDraftPath = null;
      _voiceDraftDurationMs = null;
    });
  }

  Future<void> _finishVoiceRecording({required bool sendNote}) async {
    final recordingStartedAt = _recordingStartedAt;
    final recordedDuration = recordingStartedAt == null
        ? _recordingDuration
        : DateTime.now().difference(recordingStartedAt);
    _recordingTicker?.cancel();
    _recordingTicker = null;
    final voicePath = await _audioRecorder.stop();
    if (!mounted) {
      return;
    }

    setState(() {
      _isRecordingVoice = false;
      _isVoiceRecordingPaused = false;
      _recordingDuration = Duration.zero;
      _recordingStartedAt = null;
      _voiceDraftPath = null;
      _voiceDraftDurationMs = null;
      _isVoiceHoldActive = false;
      _isVoiceRecordingLocked = false;
      _voiceSlideCancelArmed = false;
      _voiceGestureOffset = Offset.zero;
    });

    if (voicePath == null || voicePath.isEmpty) {
      return;
    }

    if (!sendNote) {
      try {
        final file = File(voicePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      return;
    }

    final durationMs = recordedDuration.inMilliseconds;
    await _sendPreparedFile(
      sendPath: voicePath,
      displayName: 'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a',
      restrictForwardAndDownload: false,
      extraMetadata: <String, dynamic>{
        'voiceNote': true,
        'durationMs': durationMs,
      },
    );
  }

  Future<void> _pauseVoiceRecording() async {
    if (!_isRecordingVoice || _isVoiceRecordingPaused) return;
    try {
      await _audioRecorder.pause();
      if (!mounted) return;
      setState(() {
        _isVoiceRecordingPaused = true;
      });
    } catch (_) {}
  }

  Future<void> _resumeVoiceRecording() async {
    if (!_isRecordingVoice || !_isVoiceRecordingPaused) return;
    try {
      await _audioRecorder.resume();
      if (!mounted) return;
      setState(() {
        _isVoiceRecordingPaused = false;
      });
    } catch (_) {}
  }

  Future<void> _stopVoiceRecordingKeepDraft() async {
    // Stop recording but don't send. Creates a local draft with send/delete.
    if (!_isRecordingVoice) return;
    try {
      final recordingStartedAt = _recordingStartedAt;
      final recordedDuration = recordingStartedAt == null
          ? _recordingDuration
          : DateTime.now().difference(recordingStartedAt);
      _recordingTicker?.cancel();
      _recordingTicker = null;
      final voicePath = await _audioRecorder.stop();
      if (!mounted) return;
      // If stop failed, keep state.
      if (voicePath == null || voicePath.isEmpty) {
        return;
      }
      setState(() {
        _isRecordingVoice = false;
        _isVoiceRecordingPaused = false;
        _recordingStartedAt = null;
        _voiceDraftPath = voicePath;
        _voiceDraftDurationMs = recordedDuration.inMilliseconds;
        _isVoiceHoldActive = false;
        _isVoiceRecordingLocked = false;
        _voiceSlideCancelArmed = false;
        _voiceGestureOffset = Offset.zero;
      });
    } catch (_) {}
  }

  Future<void> _requestAttachmentPrint(ChatMessage message) async {
    final itemId = message.id;
    if (_printingItemIds.contains(itemId)) {
      return;
    }

    if (!message.isPrintableAttachment) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا النوع من الملفات غير قابل للطباعة.')),
      );
      return;
    }
    if (!message.attachmentDownloadAllowed) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المرسل منع طباعة هذا المرفق.')),
      );
      return;
    }
    final fileUrl = message.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      return;
    }

    final printService = ref.read(remotePrintServiceProvider);
    final catalog = await printService.fetchCatalog();
    if (!catalog.hasDesktop) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا يوجد تطبيق كمبيوتر متصل بنفس الحساب لتنفيذ الطباعة.',
          ),
        ),
      );
      return;
    }

    final selection = await _pickPrinterName(catalog);
    if (!mounted) {
      return;
    }
    if (!selection.confirmed) {
      return;
    }

    setState(() {
      _printingItemIds.add(itemId);
    });

    final clientRequestId = _itemIdToClientRequestId.putIfAbsent(
      itemId,
      () => const Uuid().v4(),
    );

    try {
      final result = await printService.requestPrintFromDownloadUrl(
        downloadUrl: _downloadUrlFor(fileUrl),
        fileName: message.fileName ?? 'attachment',
        mimeType: message.mimeType,
        preferredPrinterName: selection.printerName,
        source: 'chat_attachment_mobile',
        clientRequestId: clientRequestId,
      );

      if (result.success) {
        _itemIdToClientRequestId.remove(itemId);
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() {
          _printingItemIds.remove(itemId);
        });
      }
    }
  }

  Future<_PrinterSelectionResult> _pickPrinterName(
    RemotePrintCatalog catalog,
  ) async {
    final prefs = ref.read(userPreferencesControllerProvider).valueOrNull;
    final current = prefs?.preferredPrinterName ?? catalog.defaultPrinter;
    String? selected = current;
    final resolved = await showModalBottomSheet<_PrinterSelectionResult>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'اختر الطابعة',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  RadioListTile<String?>(
                    value: null,
                    // ignore: deprecated_member_use
                    groupValue: selected,
                    title: const Text('الطابعة الافتراضية على الكمبيوتر'),
                    // ignore: deprecated_member_use
                    onChanged: (value) => setModalState(() => selected = value),
                  ),
                  if (catalog.printers.isNotEmpty)
                    ...catalog.printers.map(
                      (printer) => RadioListTile<String?>(
                        value: printer,
                        // ignore: deprecated_member_use
                        groupValue: selected,
                        title: Text(printer),
                        // ignore: deprecated_member_use
                        onChanged: (value) =>
                            setModalState(() => selected = value),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(
                            const _PrinterSelectionResult(
                              confirmed: false,
                              printerName: null,
                            ),
                          ),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(
                            _PrinterSelectionResult(
                              confirmed: true,
                              printerName: selected,
                            ),
                          ),
                          child: const Text('تأكيد'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final result =
        resolved ??
        const _PrinterSelectionResult(confirmed: false, printerName: null);
    if (result.confirmed) {
      await ref
          .read(userPreferencesControllerProvider.notifier)
          .setPreferredPrinterName(result.printerName);
    }
    return result;
  }

  String _downloadUrlFor(String fileUrl) {
    final uri = Uri.parse(fileUrl);
    final segments = List<String>.from(uri.pathSegments);
    if (segments.isNotEmpty && segments.last == 'file') {
      segments[segments.length - 1] = 'download';
      return uri.replace(pathSegments: segments).toString();
    }
    return fileUrl;
  }

  Future<void> _downloadAttachment(
    ChatMessage message, {
    bool openAfterDownload = false,
    bool forceRedownload = false,
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
      final repository = ref.read(chatRepositoryProvider);
      final isCached = !forceRedownload && await repository.isAttachmentCached(message);

      // Register download state for this message only if we actually need to download
      if (!isCached && mounted) {
        setState(() {
          _downloadStates[message.id] = _MessageDownloadState(
            fileName: message.fileName ?? 'مرفق',
            progress: 0,
          );
        });
      }
      final localPath = await repository.downloadAttachment(
        message,
        forceRefresh: forceRedownload,
        onProgress: (received, total) {
          if (!mounted) {
            return;
          }
          setState(() {
            _downloadStates[message.id] = _MessageDownloadState(
              fileName: message.fileName ?? 'مرفق',
              progress: total <= 0
                  ? 0
                  : (received / total).clamp(0, 1).toDouble(),
            );
          });
        },
      );
      _cachedAttachmentIds.add(message.id);
      _checkedAttachmentIds.add(message.id);
      if (!mounted) return;

      if (openAfterDownload) {
        final result = await OpenFilex.open(localPath);
        if (!mounted) return;

        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.message.isNotEmpty ? result.message : 'تعذر فتح المرفق',
              ),
            ),
          );
        }
      } else {
        final savedFolder = await _saveAttachmentForMobile(
          message: message,
          localPath: localPath,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حفظ ${message.fileName ?? 'المرفق'} بنجاح\nمسار الحفظ: $savedFolder',
            ),
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
          _downloadStates.remove(message.id);
        });
      }
    }
  }

  Future<String> _saveAttachmentForMobile({
    required ChatMessage message,
    required String localPath,
  }) async {
    final sourceFile = File(localPath);
    if (!sourceFile.existsSync()) {
      throw Exception('الملف غير متوفر محليًا');
    }

    final isVideo = (message.mimeType?.startsWith('video/') ?? false) ||
        ['.mp4', '.mov', '.avi', '.mkv'].contains(
          p.extension(message.fileName ?? localPath).toLowerCase(),
        );

    if (message.isImageMessage) {
      await Gal.putImage(localPath, album: 'Workplace Chat');
      return 'معرض الصور (Workplace Chat)';
    }

    if (isVideo) {
      await Gal.putVideo(localPath, album: 'Workplace Chat');
      return 'معرض الفيديوهات (Workplace Chat)';
    }

    if (Platform.isAndroid) {
      final bytes = await sourceFile.readAsBytes();
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ الملف',
        fileName: p.basename(message.fileName ?? localPath),
        bytes: Uint8List.fromList(bytes),
      );
      if (savedPath == null || savedPath.trim().isEmpty) {
        throw Exception('تم إلغاء حفظ الملف.');
      }
      return 'المكان الذي اخترته';
    }

    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مكان حفظ الملف',
    );
    final fallbackDirectory = await _resolveMobileFallbackDirectory();
    final directoryPath =
        (selectedDirectory != null && selectedDirectory.isNotEmpty)
        ? selectedDirectory
        : fallbackDirectory.path;
    final destinationPath = _resolveUniquePath(
      directoryPath,
      p.basename(message.fileName ?? localPath),
    );
    await sourceFile.copy(destinationPath);
    return p.dirname(destinationPath);
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

      final ext = resolveStickerExtension(bytes, message.fileName);
      final safeName = message.fileName != null
          ? '${p.basenameWithoutExtension(message.fileName!)}$ext'
          : 'sticker_${message.id.substring(0, 6)}$ext';

      await saveLocalSticker(
        name: safeName,
        bytes: bytes,
        repository: ref.read(chatRepositoryProvider),
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

  Future<Directory> _resolveMobileFallbackDirectory() async {
    final appDocuments = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(appDocuments.path, 'iSmart Messenger', 'Storage', 'Documents'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _resolveUniquePath(String directoryPath, String fileName) {
    final baseName = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidate = p.join(directoryPath, fileName);
    var counter = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(directoryPath, '${baseName}_$counter$extension');
      counter++;
    }
    return candidate;
  }

  Future<void> _openAttachment(ChatMessage message) async {
    if (message.isImageMessage) {
      return _showImagePreview(message);
    }
    if (!message.attachmentDownloadAllowed) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا الملف للعرض فقط داخل الشات.')),
      );
      return;
    }

    // If already downloaded/cached on the phone, open directly without re-downloading!
    final repository = ref.read(chatRepositoryProvider);
    final cachedPath = await repository.getCachedAttachmentPath(message);

    if (cachedPath != null && await File(cachedPath).exists()) {
      _cachedAttachmentIds.add(message.id);
      _checkedAttachmentIds.add(message.id);
      final result = await OpenFilex.open(cachedPath);
      if (!mounted) return;

      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isNotEmpty
                  ? result.message
                  : 'تعذر فتح الملف باستخدام التطبيقات المتوفرة على الهاتف',
            ),
          ),
        );
      }
      return;
    }

    // If not cached yet, download once and open
    return _downloadAttachment(message, openAfterDownload: true);
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;
    if (_showScrollToLatestButton || _unreadBelowCount > 0) {
      setState(() {
        _showScrollToLatestButton = false;
        _unreadBelowCount = 0;
      });
    }
    if (animated) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(0);
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels < 50;
  }

  List<ChatMessage> _deduplicateMessagesById(List<ChatMessage> input) {
    if (input.length < 2) {
      return input;
    }
    final seen = <String>{};
    final deduped = <ChatMessage>[];
    for (final message in input) {
      if (seen.add(message.id)) {
        deduped.add(message);
      }
    }
    return deduped;
  }

  List<ChatMessage> _collapseMediaAlbums(List<ChatMessage> messages) {
    final displayed = <ChatMessage>[];
    final seenGroups = <String>{};
    for (final message in messages) {
      final groupId = message.isImageMessage
          ? (message.metadata?['mediaGroupId']?.toString())
          : null;
      if (groupId != null && groupId.isNotEmpty) {
        if (!seenGroups.add(groupId)) continue;
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

  void _toggleMessageSelection(String messageId) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
        _replyingTo = null;
        _editingMessage = null;
      }
    });
  }

  void _clearSelection() {
    if (_selectedMessageIds.isEmpty) {
      return;
    }
    setState(() {
      _selectedMessageIds.clear();
    });
  }

  Future<void> _scrollToMessageById(String messageId) async {
    for (int attempt = 0; attempt < 6; attempt++) {
      var key = _messageKeys[messageId];
      var targetContext = key?.currentContext;
      if ((targetContext == null || !targetContext.mounted) &&
          _scrollController.hasClients) {
        final messages = ref
            .read(conversationMessagesControllerProvider(widget.conversation.id))
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
              await Future<void>.delayed(const Duration(milliseconds: 40));
              if (!mounted) return;
              key = _messageKeys[messageId];
              targetContext = key?.currentContext;
            }
          }
        }
      }
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.25,
        );
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 70));
      if (!mounted) return;
    }
  }


  Future<void> _jumpToRepliedMessage(String replyId) async {
    await _scrollToMessageById(replyId);
    if (!mounted) return;
    setState(() => _focusedMessageId = replyId);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    setState(() => _focusedMessageId = null);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() => _focusedMessageId = replyId);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    if (_focusedMessageId == replyId) {
      setState(() => _focusedMessageId = null);
    }
  }

  void _handleDoubleTapReaction(ChatMessage message) {
    HapticFeedback.mediumImpact();
    ref
        .read(
          conversationMessagesControllerProvider(
            widget.conversation.id,
          ).notifier,
        )
        .toggleReaction(
          messageId: message.id,
          emoji: '❤️',
        );

    setState(() {
      _pulsingHeartMessageId = message.id;
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && _pulsingHeartMessageId == message.id) {
        setState(() => _pulsingHeartMessageId = null);
      }
    });
  }

  String _formatReceiptDateTime(DateTime? dateTime) {
    if (dateTime == null) return '—';
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final diff = today.difference(target).inDays;
    final hour = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'م' : 'ص';
    final timeStr = '$hour:$minute $period';

    if (diff == 0) {
      return 'اليوم في $timeStr';
    } else if (diff == 1) {
      return 'أمس في $timeStr';
    } else {
      const months = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      return '${local.day} ${months[local.month - 1]} ${local.year}، $timeStr';
    }
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

  Future<Map<String, dynamic>?> _pickBroadcastTargetsMetadata() async {
    if (_data.type != 'broadcast') {
      return null;
    }

    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    final departments = overview?.departments ?? const <DepartmentSummary>[];
    final users = overview?.users ?? const <ChatDirectoryUser>[];
    final currentUserId =
        ref.read(authControllerProvider).valueOrNull?.id ?? '';

    final payload = await BroadcastTargetPickerSheet.show(
      context,
      departments: departments,
      users: users,
      currentUserId: currentUserId,
      initialSendToAll: _broadcastSendToAllDepartments,
      initialDepartmentIds: _broadcastTargetDepartmentIds,
      initialUserIds: _broadcastTargetUserIds,
    );

    if (payload == null) {
      return null;
    }

    final rawTargets =
        payload['broadcastTargets'] as Map<String, dynamic>? ?? {};
    final bool isAll = rawTargets['sentToAllDepartments'] == true;
    final deptIds = (rawTargets['departmentIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toSet();
    final userIds = (rawTargets['userIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toSet();

    _broadcastSendToAllDepartments = isAll;
    _broadcastTargetDepartmentIds = isAll ? <String>{} : deptIds;
    _broadcastTargetUserIds = isAll ? <String>{} : userIds;

    return payload;
  }

  Map<String, dynamic> _forwardMetadataFor(ChatMessage message) {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    return {
      'forwardedFrom': {
        'conversationId': message.conversationId,
        'conversationName': _data.displayTitle(authUser?.id ?? ''),
        'senderId': message.sender?.id ?? message.senderId,
        'senderName': message.sender?.displayName ?? 'عضو',
        'messageId': message.id,
        'messageType': message.messageType,
        'forwardedAt': DateTime.now().toUtc().toIso8601String(),
      },
    };
  }

  String? _replyPreviewFor(
    ChatMessage message,
    Map<String, ChatMessage> messagesById,
  ) {
    final replyId = message.replyToMessageId;
    if (replyId == null || replyId.isEmpty) {
      return null;
    }
    final replied = messagesById[replyId];
    if (replied == null) {
      return message.replyPreviewText ?? 'الرسالة الأصلية';
    }
    if (replied.content.isNotEmpty) {
      return replied.content;
    }
    return replied.fileName ?? 'ملف مرفق';
  }

  String? _replyPreviewSenderFor(
    ChatMessage message,
    Map<String, ChatMessage> messagesById,
  ) {
    final replyId = message.replyToMessageId;
    if (replyId == null || replyId.isEmpty) {
      return null;
    }
    final replied = messagesById[replyId];
    if (replied != null) {
      final senderName = replied.sender?.displayName ?? 'عضو';
      return senderName.trim().isEmpty ? null : senderName;
    }
    return message.replyPreviewSender;
  }

  Future<void> _jumpToSearchMessage(
    ChatMessage message, {
    String? query,
  }) async {
    await ref
        .read(
          conversationMessagesControllerProvider(
            widget.conversation.id,
          ).notifier,
        )
        .hydrateMessages([message]);
    if (!mounted) {
      return;
    }
    setState(() {
      _focusedMessageId = message.id;
      _selectedMessageIds.clear();
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted) {
      return;
    }
    await _scrollToMessageById(message.id);
    if (!mounted || query == null || query.trim().isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم الانتقال إلى نتيجة البحث: ${query.trim()}'),
        duration: const Duration(seconds: 2),
      ),
    );
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

    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    if (overview == null) {
      return;
    }

    final currentUserId =
        ref.read(authControllerProvider).valueOrNull?.id ?? '';

    final targets = await ChatForwardSheet.show(
      context,
      currentUserId: currentUserId,
      currentConversationId: widget.conversation.id,
      selectedMessageCount: selectedMessages.length,
    );

    if (targets == null || targets.isEmpty) {
      return;
    }

    // Filter restricted attachments
    var skippedRestrictedCount = 0;
    final validMessages = <ChatMessage>[];
    for (final message in selectedMessages) {
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
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
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
              ChatConversation? existingDirect;
              for (final conv in overview.conversations) {
                if (conv.type == 'direct') {
                  final isWithTarget =
                      conv.members.any((m) => m.id == target.user!.id);
                  if (isWithTarget) {
                    existingDirect = conv;
                    break;
                  }
                }
              }

              if (existingDirect != null) {
                targetConversationIds.add(existingDirect.id);
              } else {
                final created = await repository.createDirectConversation(
                  target.user!.id,
                );
                targetConversationIds.add(created.id);
              }
              targetNames.add(target.title);
            }
            break;

          case ForwardTargetKind.department:
            if (target.department != null) {
              final dept = target.department!;
              ChatConversation? deptRoom;
              for (final conv in overview.conversations) {
                if (conv.departmentId == dept.id ||
                    conv.id == dept.defaultConversationId) {
                  deptRoom = conv;
                  break;
                }
              }

              if (deptRoom != null) {
                targetConversationIds.add(deptRoom.id);
                targetNames.add('غرفة ${dept.name}');
              } else {
                final deptUsers = overview.users
                    .where(
                      (u) =>
                          u.departmentId == dept.id &&
                          u.id != currentUserId,
                    )
                    .toList();

                if (deptUsers.isEmpty) {
                  targetNames.add(dept.name);
                } else {
                  targetNames.add('${dept.name} (${deptUsers.length} أعضاء)');
                  for (final member in deptUsers) {
                    ChatConversation? memberConv;
                    for (final conv in overview.conversations) {
                      if (conv.type == 'direct' &&
                          conv.members.any((m) => m.id == member.id)) {
                        memberConv = conv;
                        break;
                      }
                    }
                    if (memberConv != null) {
                      targetConversationIds.add(memberConv.id);
                    } else {
                      try {
                        final created =
                            await repository.createDirectConversation(
                              member.id,
                            );
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }


  Future<void> _retryMessage(ChatMessage message) async {
    try {
      await ref
          .read(
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
          )
          .retryMessage(message);
    } catch (_) {
      // Handled and marked as failed by ConversationMessagesController
    }
  }

  Future<void> _showWhatsAppContextMenu(ChatMessage message) async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }

    HapticFeedback.heavyImpact();
    final authUser = ref.read(authControllerProvider).valueOrNull;
    final senderId = message.sender?.id ?? message.senderId;
    final isMine = authUser?.id.toString() == senderId.toString();
    final canDelete = isMine || authUser?.can('canDeleteMessages') == true;
    final canEdit = isMine && !message.hasAttachment && !message.isDeleted;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFailed = message.isFailed;
    final previewText = message.content.isNotEmpty
        ? message.content
        : (message.fileName ?? 'مرفق');

    final quickEmojis = ['❤️', '👍', '😂', '😮', '😢', '🙏'];
    final statusObj = authUser == null || !isMine ? null : _status(message, authUser.id);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final textTheme = Theme.of(context).textTheme;
        return Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
              decoration: TextDecoration.none,
              color: isDark ? Colors.white : Colors.black87,
            ),
            child: GestureDetector(
              onTap: () => Navigator.of(dialogContext).pop(),
              behavior: HitTestBehavior.opaque,
              child: SafeArea(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: GestureDetector(
                    onTap: () {}, // Prevent tap through
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        // 1. Floating Reactions Capsule (WhatsApp iOS Style)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                            border: Border.all(
                              color: isDark ? Colors.white12 : const Color(0x0F000000),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...quickEmojis.map((emoji) {
                                final isReacted = _reactionEntries(message).any((entry) => entry.key == emoji && _reactionHasUser(entry.value, authUser?.id));
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.of(dialogContext).pop();
                                    ref
                                        .read(
                                          conversationMessagesControllerProvider(
                                            widget.conversation.id,
                                          ).notifier,
                                        )
                                        .toggleReaction(
                                          messageId: message.id,
                                          emoji: emoji,
                                        );
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isReacted
                                          ? (isDark
                                              ? Colors.white24
                                              : const Color(0xFFE5E5EA))
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 26, decoration: TextDecoration.none),
                                    ),
                                  ),
                                );
                              }),
                              // Add reaction (+) button
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  _showFullReactionPicker(message);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white12
                                        : const Color(0xFFF2F2F7),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    CupertinoIcons.add,
                                    size: 19,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 2. Elevated Bubble Preview (WhatsApp iOS Style)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(dialogContext).size.width * 0.78,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isMine
                                  ? (isDark
                                      ? const Color(0xFF005D4B)
                                      : const Color(0xFFE7FFDB))
                                  : (isDark
                                      ? const Color(0xFF262D31)
                                      : Colors.white),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(isMine ? 18 : 4),
                                bottomRight: Radius.circular(isMine ? 4 : 18),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isMine &&
                                    message.sender?.displayName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      message.sender!.displayName,
                                      style: const TextStyle(
                                        color: Color(0xFF3390EC),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                Text(
                                  previewText,
                                  maxLines: 5,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: isDark ? Colors.white : Colors.black87,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      DateFormat('hh:mm a').format(
                                        message.createdAt.toLocal(),
                                      ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                    if (statusObj != null) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        statusObj.icon,
                                        size: 14,
                                        color: statusObj.color,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 3. iOS Inset Context Menu Card
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 250,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : Colors.white.withValues(alpha: 0.96),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isFailed) ...[
                                  _buildWhatsAppContextMenuItem(
                                    title: 'إعادة إرسال',
                                    icon: CupertinoIcons.arrow_clockwise,
                                    isDestructive: true,
                                    onTap: () => _retryMessage(message),
                                  ),
                                  _buildWhatsAppMenuDivider(isDark),
                                ],
                                _buildWhatsAppContextMenuItem(
                                  title: 'الرد',
                                  icon: CupertinoIcons.arrowshape_turn_up_left,
                                  onTap: () {
                                    setState(() {
                                      _replyingTo = message;
                                      _editingMessage = null;
                                    });
                                  },
                                ),
                                if (message.content.trim().isNotEmpty) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: 'نسخ',
                                    icon: CupertinoIcons.doc_on_doc,
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(text: message.content),
                                      );
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('تم نسخ النص إلى الحافظة'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                _buildWhatsAppMenuDivider(isDark),
                                _buildWhatsAppContextMenuItem(
                                  title: message.isFavoritedBy(authUser?.id)
                                      ? 'إلغاء التمييز بنجمة'
                                      : 'تمييز بنجمة',
                                  icon: message.isFavoritedBy(authUser?.id)
                                      ? CupertinoIcons.star_slash
                                      : CupertinoIcons.star,
                                  onTap: () {
                                    ref
                                        .read(
                                          conversationMessagesControllerProvider(
                                            widget.conversation.id,
                                          ).notifier,
                                        )
                                        .toggleFavoriteMessage(
                                          messageId: message.id,
                                        );
                                  },
                                ),
                                if (isMine) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: 'معلومات الرسالة',
                                    icon: CupertinoIcons.info,
                                    onTap: () => _showMessageDetails(message),
                                  ),
                                ],
                                if (!message.hasAttachment ||
                                    message.attachmentForwardAllowed) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: 'إعادة توجيه',
                                    icon: CupertinoIcons.arrowshape_turn_up_right,
                                    onTap: () {
                                      setState(() {
                                        _selectedMessageIds
                                          ..clear()
                                          ..add(message.id);
                                      });
                                      _forwardSelectedMessages(
                                        ref
                                                .read(
                                                  conversationMessagesControllerProvider(
                                                    widget.conversation.id,
                                                  ),
                                                )
                                                .valueOrNull
                                                ?.messages ??
                                            const <ChatMessage>[],
                                      );
                                    },
                                  ),
                                ],
                                _buildWhatsAppMenuDivider(isDark),
                                _buildWhatsAppContextMenuItem(
                                  title: 'تحديد',
                                  icon: CupertinoIcons.checkmark_circle,
                                  onTap: () =>
                                      _toggleMessageSelection(message.id),
                                ),
                                if (message.isPrintableAttachment) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: 'طباعة عبر الكمبيوتر',
                                    icon: CupertinoIcons.printer,
                                    onTap: () =>
                                        _requestAttachmentPrint(message),
                                  ),
                                ],
                                if (message.hasAttachment &&
                                    message.attachmentDownloadAllowed) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: _cachedAttachmentIds.contains(message.id)
                                        ? 'حفظ نسخة في الجهاز'
                                        : 'حفظ في الجهاز',
                                    icon: CupertinoIcons.arrow_down_to_line,
                                    onTap: () =>
                                        _downloadAttachment(
                                          message,
                                          openAfterDownload: false,
                                          forceRedownload: true,
                                        ),
                                  ),
                                ],
                                if ((message.isStickerMessage || message.isImageMessage) &&
                                    message.attachmentDownloadAllowed) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: 'حفظ ضمن الملصقات',
                                    icon: CupertinoIcons.sparkles,
                                    onTap: () => _saveReceivedSticker(message),
                                  ),
                                ],
                                if (_canManagePinnedMessage(authUser?.id)) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: 'تثبيت الرسالة',
                                    icon: CupertinoIcons.pin,
                                    onTap: () {
                                      ref
                                          .read(
                                            chatOverviewControllerProvider.notifier,
                                          )
                                          .setGroupPinnedMessage(
                                            conversationId: widget.conversation.id,
                                            content: previewText,
                                            messageId: message.id,
                                          );
                                    },
                                  ),
                                ],
                                if (canEdit) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: 'تعديل',
                                    icon: CupertinoIcons.pencil,
                                    onTap: () {
                                      setState(() {
                                        _editingMessage = message;
                                        _replyingTo = null;
                                        _messageController.text = message.content;
                                      });
                                    },
                                  ),
                                ],
                                if (canDelete && !message.isDeleted) ...[
                                  _buildWhatsAppMenuDivider(isDark),
                                  _buildWhatsAppContextMenuItem(
                                    title: 'حذف',
                                    icon: CupertinoIcons.trash,
                                    isDestructive: true,
                                    onTap: () {
                                      ref
                                          .read(
                                            conversationMessagesControllerProvider(
                                              widget.conversation.id,
                                            ).notifier,
                                          )
                                          .deleteMessage(message.id);
                                    },
                                  ),
                                ],
                              ],
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
      ),
    );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildWhatsAppContextMenuItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).pop();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.none,
                  color: isDestructive
                      ? CupertinoColors.systemRed
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
              Icon(
                icon,
                size: 20,
                color: isDestructive
                    ? CupertinoColors.systemRed
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhatsAppMenuDivider(bool isDark) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 16,
      color: isDark ? Colors.white12 : Colors.black12,
    );
  }

  Future<void> _showActions(ChatMessage message) async {
    return _showWhatsAppContextMenu(message);
  }
  Future<void> _showFullReactionPicker(ChatMessage message) async {
    final selectedEmoji = await WhatsAppReactionPickerSheet.show(context);
    if (selectedEmoji != null && selectedEmoji.isNotEmpty && mounted) {
      await ref
          .read(
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
          )
          .toggleReaction(
            messageId: message.id,
            emoji: selectedEmoji,
          );
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String description,
    String confirmLabel = 'تأكيد',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _clearConversationForMe() async {
    final shouldClear = await _confirmAction(
      title: 'مسح الرسائل فقط',
      description: 'سيتم مسح الرسائل عندك فقط مع بقاء المحادثة في القائمة.',
      confirmLabel: 'مسح',
    );
    if (!shouldClear || !mounted) {
      return;
    }

    try {
      await ref
          .read(chatOverviewControllerProvider.notifier)
          .clearConversationMessages(widget.conversation.id);
      await ref
          .read(
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
          )
          .refresh();
      if (!mounted) return;
      setState(() {
        _selectedMessageIds.clear();
        _focusedMessageId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم مسح الرسائل عندك بنجاح')),
      );
    } catch (error) {
      final text = error.toString().toLowerCase();
      final notFound =
          text.contains('conversation not found') ||
          text.contains('404') ||
          text.contains('غير موجود');
      if (notFound && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم مسح الرسائل بالفعل')));
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteConversationForMe() async {
    final shouldDelete = await _confirmAction(
      title: 'حذف المحادثة من قائمتي',
      description: 'هل تريد حذف هذه المحادثة ومسح رسائلها من جهازك؟',
      confirmLabel: 'حذف',
    );
    if (!shouldDelete || !mounted) {
      return;
    }

    try {
      await ref
          .read(chatOverviewControllerProvider.notifier)
          .deleteConversation(widget.conversation.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _leaveConversation() async {
    final shouldLeave = await _confirmAction(
      title: 'مغادرة المجموعة',
      description: 'هل تريد مغادرة هذه المجموعة الآن؟',
      confirmLabel: 'مغادرة',
    );
    if (!shouldLeave || !mounted) {
      return;
    }
    try {
      await ref
          .read(chatOverviewControllerProvider.notifier)
          .leaveConversation(widget.conversation.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _deleteConversationForEveryone() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف نهائي للمحادثة'),
        content: const Text('سيتم حذف المحادثة ورسائلها نهائيًا للجميع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    try {
      await ref
          .read(chatOverviewControllerProvider.notifier)
          .deleteConversation(widget.conversation.id, deleteForEveryone: true);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _showMessageDetails(ChatMessage message) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final previewText = message.content.isNotEmpty
        ? message.content
        : (message.fileName ?? 'مرفق');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.45,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // iOS drag handle
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'معلومات الرسالة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        CupertinoIcons.clear_circled_solid,
                        color: isDark ? Colors.white38 : Colors.black26,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              // Message Preview Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        previewText,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          DateFormat('hh:mm a').format(
                            message.createdAt.toLocal(),
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Receipts Sections (FutureBuilder)
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: ref
                      .read(chatRepositoryProvider)
                      .getReadReceipts(message.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator.adaptive(),
                      );
                    }
                    final data = snapshot.data ?? {};
                    final rawSeenBy =
                        (data['seenBy'] as List<dynamic>? ?? []);
                    final rawDeliveredTo =
                        (data['deliveredTo'] as List<dynamic>? ?? []);
                    final isDirect = widget.conversation.type == 'direct';
                    final myId = ref.read(currentUserProvider)?.id ?? message.senderId;

                    // Exclude sender: a sender cannot be a recipient who reads/receives their own message
                    final seenBy = rawSeenBy.where((entry) {
                      final uid = (entry['_id'] ?? entry['userId'] ?? '').toString();
                      return uid.isNotEmpty && uid != myId && uid != message.senderId;
                    }).toList();

                    final deliveredTo = rawDeliveredTo.where((entry) {
                      final uid = (entry['_id'] ?? entry['userId'] ?? '').toString();
                      return uid.isNotEmpty && uid != myId && uid != message.senderId;
                    }).toList();

                    DateTime? directReadTime;
                    if (seenBy.isNotEmpty && seenBy.first['seenAt'] != null) {
                      directReadTime = DateTime.tryParse(
                        seenBy.first['seenAt'].toString(),
                      );
                    }
                    DateTime? directDeliveredTime;
                    if (deliveredTo.isNotEmpty &&
                        deliveredTo.first['deliveredAt'] != null) {
                      directDeliveredTime = DateTime.tryParse(
                        deliveredTo.first['deliveredAt'].toString(),
                      );
                    }
                    if (directReadTime != null && directDeliveredTime == null) {
                      directDeliveredTime = directReadTime;
                    }

                    final isRead = isDirect
                        ? directReadTime != null
                        : seenBy.isNotEmpty;
                    final isDelivered = isDirect
                        ? directDeliveredTime != null
                        : deliveredTo.isNotEmpty;

                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        // Section 1: قُرِئت (Read)
                        _buildReceiptsGroupCard(
                          isDark: isDark,
                          icon: Icons.done_all_rounded,
                          iconColor: isRead
                              ? const Color(0xFF34B7F1) // WhatsApp Blue Check
                              : const Color(0xFF8E8E93), // WhatsApp Grey Double Check
                          title: 'قُرِئت',
                          subtitle: isDirect
                              ? (directReadTime != null
                                  ? _formatReceiptDateTime(directReadTime)
                                  : 'لم تُقرأ بعد')
                              : (seenBy.isNotEmpty
                                  ? '${seenBy.length} من الأعضاء'
                                  : 'لم يشاهدها أحد بعد'),
                          receipts: isDirect ? [] : seenBy,
                          timeField: 'seenAt',
                        ),
                        const SizedBox(height: 16),
                        // Section 2: سُلِّمت (Delivered)
                        _buildReceiptsGroupCard(
                          isDark: isDark,
                          icon: Icons.done_all_rounded,
                          iconColor: isDelivered
                              ? const Color(0xFF8E8E93) // WhatsApp Grey Double Check
                              : (isDark ? Colors.white24 : Colors.black26),
                          title: 'سُلِّمت',
                          subtitle: isDirect
                              ? (directDeliveredTime != null
                                  ? _formatReceiptDateTime(directDeliveredTime)
                                  : 'لم تُسلّم بعد')
                              : (deliveredTo.isNotEmpty
                                  ? '${deliveredTo.length} من الأعضاء'
                                  : 'لم تُسلّم لأحد بعد'),
                          receipts: isDirect ? [] : deliveredTo,
                          timeField: 'deliveredAt',
                        ),
                        const SizedBox(height: 16),
                        // Section 3: أُرسِلت (Sent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color:
                                isDark ? const Color(0xFF2C2C2E) : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.done_rounded,
                                color: Color(0xFF8E8E93),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'أُرسِلت',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatReceiptDateTime(message.createdAt),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptsGroupCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required List<dynamic> receipts,
    required String timeField,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          if (receipts.isNotEmpty) ...[
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 16,
              color: isDark ? Colors.white12 : Colors.black12,
            ),
            ...receipts.asMap().entries.map((entry) {
              final idx = entry.key;
              final user = entry.value as Map<String, dynamic>;
              final rawTime =
                  user[timeField] ?? user['seenAt'] ?? user['deliveredAt'];
              DateTime? itemTime;
              if (rawTime != null) {
                itemTime = DateTime.tryParse(rawTime.toString());
              }
              final isLast = idx == receipts.length - 1;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        ChatAvatar(
                          avatarUrl: user['avatarUrl']?.toString() ?? '',
                          radius: 18,
                          backgroundColor: isDark
                              ? Colors.white12
                              : const Color(0xFFE5E5EA),
                          fallback: Text(
                            user['displayName']?.toString().isNotEmpty == true
                                ? user['displayName'].toString()[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            user['displayName']?.toString() ??
                                user['username']?.toString() ??
                                'مستخدم',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (itemTime != null)
                          Text(
                            _formatReceiptDateTime(itemTime),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 58,
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }


  void _showScheduledMessagesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ScheduledMessagesSheet(
        conversationId: widget.conversation.id,
        onMessageSent: () {
          ref
              .read(
                conversationMessagesControllerProvider(
                  widget.conversation.id,
                ).notifier,
              )
              .refresh();
        },
      ),
    );
  }

  Future<void> _showSearchSheet() async {
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) => ChatRemoteSearchSheet(
        conversationId: widget.conversation.id,
        onSelectMessage: (message) async {
          Navigator.of(sheetContext).pop();
          await _jumpToSearchMessage(message);
        },
      ),
    );
  }

  Future<void> _showSharedMediaSheet(
    List<ChatMessage> messages,
    String? token,
  ) async {
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

    await showModalBottomSheet<void>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => DefaultTabController(
        length: 2,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.84,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'الوسائط والمرفقات',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      _SheetCountChip(
                        label: '${sharedImages.length} صور',
                        color: const Color(0xFF3390EC),
                      ),
                      const SizedBox(width: 8),
                      _SheetCountChip(
                        label: '${sharedFiles.length} ملفات',
                        color: const Color(0xFF19A974),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: TabBar(
                    tabs: [
                      Tab(text: 'الصور'),
                      Tab(text: 'الملفات'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      sharedImages.isEmpty
                          ? const _SheetEmptyState(
                              label: 'لا توجد صور مشتركة بعد',
                            )
                          : GridView.builder(
                              cacheExtent: 0,
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              itemCount: sharedImages.length,
                              itemBuilder: (context, index) {
                                final message = sharedImages[index];
                                return InkWell(
                                  onTap: () => _showImagePreview(message),
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
                                          _ChatAttachmentImage(
                                            message: message,
                                            fit: BoxFit.cover,
                                            height: 120,
                                            width: 120,
                                          ),
                                          PositionedDirectional(
                                            top: 6,
                                            end: 6,
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
                                                        34,
                                                        34,
                                                      ),
                                                      padding: EdgeInsets.zero,
                                                    ),
                                                  )
                                                : const SizedBox.shrink(),
                                          ),
                                          Positioned(
                                            left: 6,
                                            right: 6,
                                            bottom: 6,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(
                                                  alpha: 0.45,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                DateFormat('dd/MM').format(
                                                  message.createdAt.toLocal(),
                                                ),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
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
                          ? const _SheetEmptyState(
                              label: 'لا توجد ملفات مشتركة بعد',
                            )
                          : ListView.separated(
                              cacheExtent: 0,
                              padding: const EdgeInsets.all(16),
                              itemCount: sharedFiles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final message = sharedFiles[index];
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  tileColor: Theme.of(
                                    context,
                                  ).colorScheme.surface,
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
                                    formatEgyptDateTime(
                                      message.createdAt,
                                      datePattern: 'dd/MM/yyyy',
                                      separator: ' • ',
                                    ),
                                  ),
                                  trailing: IconButton(
                                    onPressed: message.attachmentDownloadAllowed
                                        ? () => _openAttachment(message)
                                        : null,
                                    icon: Icon(
                                      _cachedAttachmentIds.contains(message.id)
                                          ? Icons.open_in_new_rounded
                                          : (message.attachmentDownloadAllowed
                                              ? Icons.download_rounded
                                              : Icons.lock_rounded),
                                    ),
                                    tooltip: _cachedAttachmentIds.contains(message.id)
                                        ? 'فتح'
                                        : (message.attachmentDownloadAllowed
                                            ? 'تنزيل'
                                            : 'عرض فقط'),
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

  Future<void> _showImagePreview(ChatMessage message) async {
    if (!mounted || message.fileUrl == null || message.fileUrl!.isEmpty) {
      return;
    }

    final allMessages =
        ref
            .read(
              conversationMessagesControllerProvider(widget.conversation.id),
            )
            .valueOrNull
            ?.messages ??
        const <ChatMessage>[];
    final groupId = message.metadata?['mediaGroupId']?.toString();
    final images = groupId == null
        ? <ChatMessage>[message]
        : allMessages
              .where(
                (m) =>
                    m.isImageMessage &&
                    m.metadata?['mediaGroupId']?.toString() == groupId,
              )
              .toList();
    final initialIndex = images
        .indexWhere((m) => m.id == message.id)
        .clamp(0, images.length - 1)
        .toInt();
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex),
              itemCount: images.length,
              itemBuilder: (_, index) => Center(
                child: InteractiveViewer(
                  child: Hero(
                    tag: 'image_${images[index].id}',
                    child: _ChatAttachmentImage(
                      message: images[index],
                      fit: BoxFit.contain,
                      height: 400,
                      width: double.infinity,
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
            PositionedDirectional(
              top: 18,
              end: 18,
              child: message.attachmentDownloadAllowed
                  ? IconButton.filledTonal(
                      onPressed: () => _startOverlayDownload(
                        message,
                        overlayContext: context,
                      ),
                      icon: const Icon(Icons.download_rounded),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  void _startOverlayDownload(
    ChatMessage message, {
    required BuildContext overlayContext,
  }) {
    Navigator.of(overlayContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_downloadAttachment(message));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final enterSendsMessage =
        ref
            .watch(userPreferencesControllerProvider)
            .valueOrNull
            ?.enterSendsMessage ??
        false;
    final overview = ref.watch(chatOverviewControllerProvider).valueOrNull;
    final selectedPeerId = _data.type == 'direct'
        ? _data.members
              .cast<ChatDirectoryUser?>()
              .firstWhere(
                (entry) => entry?.id != authUser?.id,
                orElse: () => null,
              )
              ?.id
        : null;
    final tokenAsync = ref.watch(authTokenProvider);
    final token = tokenAsync.valueOrNull;

    final messagesState = ref.watch(
      conversationMessagesControllerProvider(widget.conversation.id),
    );
    final loadedMessages =
        messagesState.valueOrNull?.messages ?? const <ChatMessage>[];
    _syncCachedAttachments(loadedMessages);

    final peer = selectedPeerId == null
        ? null
        : (overview?.users.cast<ChatDirectoryUser?>().firstWhere(
                (entry) => entry?.id == selectedPeerId,
                orElse: () => null,
              ) ??
              _data.members.cast<ChatDirectoryUser?>().firstWhere(
                (entry) => entry?.id == selectedPeerId,
                orElse: () => null,
              ));
    final isBlockedFromSending = _isBlockedFromSending(authUser?.id);
    final isBroadcastReadOnly = _data.type == 'broadcast'
        ? !_canPublishInBroadcast(authUser?.id)
        : false;
    final isReadOnly =
        !_data.isActive || isBlockedFromSending || isBroadcastReadOnly;
    final statusText = peer == null ? 'محادثة داخلية' : _presenceLabel(peer);
    final statusColor = isReadOnly
        ? const Color(0xFFF59E0B)
        : (peer == null
              ? colorScheme.onSurfaceVariant
              : _presenceColor(peer.presenceStatus));
    final effectiveStatusText = isReadOnly
        ? (isBlockedFromSending
              ? 'تم تقييدك: قراءة فقط'
              : (isBroadcastReadOnly
                    ? 'قناة بث: لا تملك صلاحية الإرسال'
                    : 'الغرفة معطلة بواسطة المشرف'))
        : statusText;
    final canDeleteForEveryone = authUser?.role == 'admin' ||
        _data.createdBy == authUser?.id ||
        _data.type == 'direct';
    final canManagePinnedMessage = _canManagePinnedMessage(authUser?.id);
    final typingIndicatorText = _typingUsers.isEmpty
        ? null
        : (_data.type == 'direct'
              ? 'يكتب الآن...'
              : '${_typingUsers.values.join('، ')} يكتب الآن...');

    final peerJobAndBranch = [
      if (peer != null && peer.jobTitle.trim().isNotEmpty) peer.jobTitle.trim(),
      if (peer != null && peer.branchCode.trim().isNotEmpty) 'فرع ${peer.branchCode.trim()}',
    ].join(' • ');

    final chatSubtitleText = typingIndicatorText ??
        (peerJobAndBranch.isNotEmpty
            ? '$peerJobAndBranch | $effectiveStatusText'
            : effectiveStatusText);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _clearActiveConversationSelection();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          titleSpacing: 0,
          elevation: 0,
          backgroundColor: colorScheme.surface.withValues(alpha: 0.75),
          surfaceTintColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
              child: Container(color: Colors.transparent),
            ),
          ),
          title: _selectionMode
              ? Text('${_selectedMessageIds.length} محددة')
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final result = await navigator.push(
                      CupertinoPageRoute(
                        builder: (_) => ConversationDetailsScreen(
                          conversation: _data,
                          peer: peer,
                          messages: loadedMessages,
                          token: token,
                        ),
                      ),
                    );
                    if (result == 'deleted' && mounted) {
                      navigator.pop();
                      return;
                    }
                    if (result is ChatConversation && mounted) {
                      setState(() {
                        _conversation = result;
                      });
                    }
                  },
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        child: ((_data.type == 'direct' ? peer?.avatarUrl : _data.avatarUrl) ?? _data.avatarUrl ?? peer?.avatarUrl)?.isNotEmpty == true
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: ((_data.type == 'direct' ? peer?.avatarUrl : _data.avatarUrl) ?? _data.avatarUrl ?? peer?.avatarUrl)!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  httpHeaders: token == null || token.isEmpty
                                      ? null
                                      : {'Authorization': 'Bearer $token'},
                                  errorWidget: (_, __, ___) => Icon(
                                    _data.type == 'group'
                                        ? Icons.groups_outlined
                                        : Icons.person_outline,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Icon(
                                _data.type == 'group'
                                    ? Icons.groups_outlined
                                    : Icons.person_outline,
                                color: colorScheme.onSurfaceVariant,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _data.displayTitle(authUser?.id ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              chatSubtitleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: typingIndicatorText != null
                                    ? const Color(0xFF34C759)
                                    : statusColor,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          actions: [
            if (_selectionMode) ...[
              IconButton(
                onPressed: () => _forwardSelectedMessages(loadedMessages),
                icon: const Icon(Icons.forward_to_inbox_rounded),
                tooltip: 'إعادة توجيه المحدد',
              ),
              IconButton(
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إلغاء التحديد',
              ),
            ] else ...[
              if (_data.type == 'group' && _data.createdBy == authUser?.id)
                IconButton(
                  onPressed: () async {
                    final updated = await Navigator.of(context)
                        .push<ChatConversation>(
                          MaterialPageRoute(
                            builder: (_) =>
                                GroupManagementScreen(conversation: _data),
                          ),
                        );
                    if (updated != null && mounted) {
                      setState(() => _conversation = updated);
                    }
                  },
                  icon: const Icon(Icons.group_outlined),
                  tooltip: 'إدارة المجموعة',
                ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'search') {
                    _showSearchSheet();
                    return;
                  }
                  if (value == 'media') {
                    _showSharedMediaSheet(loadedMessages, token);
                    return;
                  }
                  if (value == 'scheduled') {
                    _showScheduledMessagesSheet();
                    return;
                  }
                  if (value == 'delete_self') {
                    await _deleteConversationForMe();
                    return;
                  }
                  if (value == 'clear') {
                    await _clearConversationForMe();
                    return;
                  }
                  if (value == 'leave') {
                    await _leaveConversation();
                    return;
                  }
                  if (value == 'delete_everyone') {
                    await _deleteConversationForEveryone();
                    return;
                  }
                  if (value == 'appearance') {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChatAppearanceScreen(),
                      ),
                    );
                    return;
                  }
                  if (value == 'set_pinned_message') {
                    await _upsertPinnedMessage(edit: false);
                    return;
                  }
                  if (value == 'edit_pinned_message') {
                    await _upsertPinnedMessage(edit: true);
                    return;
                  }
                  if (value == 'clear_pinned_message') {
                    await _clearPinnedMessage();
                    return;
                  }
                  final updated = await ref
                      .read(chatOverviewControllerProvider.notifier)
                      .updateConversationPreferences(
                        conversationId: widget.conversation.id,
                        isPinned: value == 'pin' ? !_data.isPinned : null,
                        isMuted: value == 'mute' ? !_data.isMuted : null,
                        isFavorite: value == 'favorite'
                            ? !_data.isFavorite
                            : null,
                        isArchived: value == 'archive'
                            ? !_data.isArchived
                            : null,
                      );
                  if (!mounted) return;
                  setState(() => _conversation = updated);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'search',
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, size: 20),
                        SizedBox(width: 10),
                        Text('بحث في المحادثة'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'media',
                    child: Row(
                      children: [
                        Icon(Icons.perm_media_outlined, size: 20),
                        SizedBox(width: 10),
                        Text('الوسائط والمستندات'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'scheduled',
                    child: Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 20),
                        SizedBox(width: 10),
                        Text('الرسائل المجدولة'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(
                      _data.isPinned ? 'إزالة التثبيت' : 'تثبيت المحادثة',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'mute',
                    child: Text(
                      _data.isMuted ? 'إلغاء الكتم' : 'كتم الإشعارات',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      _data.isArchived ? 'إلغاء الأرشفة' : 'أرشفة المحادثة',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'favorite',
                    child: Text(
                      _data.isFavorite
                          ? 'إزالة من المفضلة'
                          : 'إضافة إلى المفضلة',
                    ),
                  ),
                  if (canManagePinnedMessage && _data.pinnedMessage == null)
                    const PopupMenuItem(
                      value: 'set_pinned_message',
                      child: Text('إضافة رسالة مثبتة'),
                    ),
                  if (canManagePinnedMessage && _data.pinnedMessage != null)
                    const PopupMenuItem(
                      value: 'edit_pinned_message',
                      child: Text('تعديل الرسالة المثبتة'),
                    ),
                  if (canManagePinnedMessage && _data.pinnedMessage != null)
                    const PopupMenuItem(
                      value: 'clear_pinned_message',
                      child: Text('حذف الرسالة المثبتة'),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'appearance',
                    child: Text('مظهر المحادثات'),
                  ),
                  const PopupMenuItem(
                    value: 'delete_self',
                    child: Text(
                      'حذف المحادثة من قائمتي',
                      style: TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text('مسح الرسائل فقط'),
                  ),
                  if (_data.type != 'direct')
                    const PopupMenuItem(
                      value: 'leave',
                      child: Text('مغادرة المجموعة'),
                    ),
                  if (canDeleteForEveryone)
                    PopupMenuItem(
                      value: 'delete_everyone',
                      child: Text(
                        _data.type == 'direct'
                            ? 'حذف نهائي للطرفين'
                            : 'حذف نهائي للجميع',
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ),
                ],
              ),
            ],
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(0.5),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: ChatBackdrop(
                preferences:
                    authUser?.chatPreferences ?? ChatPreferences.defaults,
                isDark: theme.brightness == Brightness.dark,
              ),
            ),
            Column(
              children: [
                if (isReadOnly ||
                    (_data.pinnedMessage != null &&
                        _data.pinnedMessage!.content.trim().isNotEmpty))
                  SizedBox(
                    height: MediaQuery.of(context).padding.top + kToolbarHeight,
                  ),
                if (isReadOnly)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF5D38A)),
                    ),
                    child: Text(
                      _readOnlyTextFor(authUser?.id),
                      style: const TextStyle(color: Color(0xFF9A6400)),
                    ),
                  ),
                if (_data.pinnedMessage != null &&
                    _data.pinnedMessage!.content.trim().isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      if (_data.pinnedMessage!.messageId != null) {
                        _scrollToMessageById(_data.pinnedMessage!.messageId!);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.push_pin_rounded, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'رسالة مثبتة',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(_data.pinnedMessage!.content),
                              ],
                            ),
                          ),
                          if (canManagePinnedMessage)
                            PopupMenuButton<String>(
                              tooltip: 'إدارة الرسالة المثبتة',
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await _upsertPinnedMessage(edit: true);
                                } else if (value == 'remove') {
                                  await _clearPinnedMessage();
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('تعديل'),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('إزالة'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: messagesState.when(
                    skipLoadingOnReload: true,
                    skipLoadingOnRefresh: true,
                    skipError: true,
                    loading: () => const _ChatMessagesLoadingSkeleton(),
                    error: (error, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 48,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'تعذر تحميل الرسائل',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => ref
                                .read(
                                  conversationMessagesControllerProvider(
                                    widget.conversation.id,
                                  ).notifier,
                                )
                                .refresh(),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                    data: (messagesData) {
                      final messages = _deduplicateMessagesById(
                        messagesData.messages,
                      );
                      final renderedMessages = _collapseMediaAlbums(messages);
                      final visibleIds = messages
                          .map((message) => message.id)
                          .toSet();
                      _messageKeys.removeWhere(
                        (messageId, _) => !visibleIds.contains(messageId),
                      );
                      final messagesById = {
                        for (final message in messages) message.id: message,
                      };

                      if (messages.isEmpty) {
                        _lastMessageCount = 0;
                        return Center(
                          child: Text(
                            'لا توجد رسائل بعد',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }

                      if (_lastMessageCount == 0 && messages.isNotEmpty) {
                        _animatedMessageIds.addAll(messages.map((m) => m.id));
                        _animatedMessageIds.addAll(
                          messages
                              .map((m) => m.metadata?['clientMessageId']?.toString())
                              .whereType<String>(),
                        );
                      }

                      final hasNewMessages =
                          messages.length > _lastMessageCount;
                      final shouldAutoScroll =
                          _isNearBottom() && !_isLoadingMore;

                      if (hasNewMessages && shouldAutoScroll && _lastMessageCount > 0) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _scrollToBottom(animated: true);
                        });
                      } else if (hasNewMessages && !shouldAutoScroll && _lastMessageCount > 0) {
                        _unreadBelowCount += (messages.length - _lastMessageCount);
                      }

                      _lastMessageCount = messages.length;

                      final hasTopBanner =
                          isReadOnly ||
                          (_data.pinnedMessage != null &&
                              _data.pinnedMessage!.content.trim().isNotEmpty);

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          hasTopBanner
                              ? 18
                              : (MediaQuery.of(context).padding.top +
                                    kToolbarHeight +
                                    18),
                          16,
                          24,
                        ),
                        itemCount:
                            renderedMessages.length +
                            (messagesData.isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= renderedMessages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                child: AppLoadingIndicator(size: 28),
                              ),
                            );
                          }

                          final message = renderedMessages[index];
                          final older = index < renderedMessages.length - 1
                              ? renderedMessages[index + 1]
                              : null;
                          final newer = index > 0
                              ? renderedMessages[index - 1]
                              : null;

                          final messageLocalDate = message.createdAt.toLocal();
                          final olderLocalDate = older?.createdAt
                              .toLocal();

                          final showDate =
                              olderLocalDate == null ||
                              olderLocalDate.day != messageLocalDate.day ||
                              olderLocalDate.month !=
                                  messageLocalDate.month ||
                              olderLocalDate.year != messageLocalDate.year;

                          final senderId =
                              message.sender?.id ?? message.senderId;

                          final isMine =
                              authUser?.id.toString() == senderId.toString();

                          final isLastInGroup =
                              newer == null ||
                              newer.sender?.id != message.sender?.id ||
                              newer.createdAt
                                      .difference(message.createdAt)
                                      .inMinutes >
                                  6;

                          final senderName =
                              message.sender?.displayName.isNotEmpty == true
                              ? message.sender!.displayName
                              : (isMine ? 'أنت' : 'عضو');

                          final screenW = MediaQuery.sizeOf(context).width;
                          final maxBubbleWidth = math.min(
                            480.0,
                            screenW * (message.hasAttachment ? 0.82 : 0.78),
                          );

                          /// رسايلي يمين - رسايل الطرف التاني شمال
                          final bubbleAlignment = isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft;

                          final replyPreview = _replyPreviewFor(
                            message,
                            messagesById,
                          );
                          final replyPreviewSender = _replyPreviewSenderFor(
                            message,
                            messagesById,
                          );

                          final status = authUser == null || !isMine
                              ? null
                              : _status(message, authUser.id);

                          final isDark = theme.brightness == Brightness.dark;
                          final chatPreferences =
                              authUser?.chatPreferences ??
                              ChatPreferences.defaults;
                          final resolved =
                              ChatAppearanceCatalog.resolveAppearance(
                                preferences: chatPreferences,
                                isDark: isDark,
                                colorScheme: colorScheme,
                              );

                          final bubbleColor = isMine
                              ? resolved.outgoingBubbleColors.first
                              : resolved.incomingBubbleColor;
                          final textColor = isMine
                              ? resolved.outgoingTextColor
                              : resolved.incomingTextColor;
                          final subTextColor = isMine
                              ? const Color(0xFF64748B)
                              : colorScheme.onSurfaceVariant;

                          final replyBgColor = isMine
                              ? resolved.outgoingReplyColor
                              : resolved.incomingReplyColor;

                          final bubbleBorderColor = isMine
                              ? resolved.outgoingBorderColor
                              : resolved.incomingBorderColor;
                          final isSelected = _selectedMessageIds.contains(
                            message.id,
                          );
                          final isFocused = _focusedMessageId == message.id;
                          final isFavorited = message.isFavoritedBy(authUser?.id);
                          final albumMessages = _albumFor(message, messages);
                          final stableItemKey =
                              message.metadata?['clientMessageId']
                                  ?.toString() ??
                              message.id;
                          final messageGlobalKey = _messageKeys.putIfAbsent(
                            stableItemKey,
                            GlobalKey.new,
                          );
                          _messageKeys[message.id] = messageGlobalKey;

                          Widget child = RepaintBoundary(
                            key: ValueKey(stableItemKey),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showDate)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: Text(
                                        _formatDateDivider(messageLocalDate),
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                SwipeTo(
                                  onRightSwipe: (details) {
                                    setState(() => _replyingTo = message);
                                  },
                                  onLeftSwipe: (details) {
                                    setState(() => _replyingTo = message);
                                  },
                                  child: Align(
                                    alignment: bubbleAlignment,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _selectionMode
                                          ? () => _toggleMessageSelection(
                                              message.id,
                                            )
                                          : () {
                                              FocusScope.of(context).unfocus();
                                            },
                                      onDoubleTap: () =>
                                          _handleDoubleTapReaction(message),
                                      onLongPress: () {
                                        if (_selectionMode) {
                                          _toggleMessageSelection(message.id);
                                        } else {
                                          _showWhatsAppContextMenu(message);
                                        }
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: isMine
                                            ? MainAxisAlignment.end
                                            : MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Flexible(
                                            child: ConstrainedBox(
                                              key: messageGlobalKey,
                                              constraints: BoxConstraints(
                                                maxWidth: maxBubbleWidth
                                                    .clamp(200.0, 480.0)
                                                    .toDouble(),
                                              ),
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment: isMine
                                                        ? CrossAxisAlignment.end
                                                        : CrossAxisAlignment
                                                              .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      AnimatedContainer(
                                                          duration:
                                                              const Duration(
                                                                milliseconds: 180,
                                                              ),
                                                          margin: EdgeInsets.only(
                                                            bottom: 6,
                                                            left: isMine ? 34 : 0,
                                                            right: isMine
                                                                ? 0
                                                                : 34,
                                                          ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 14,
                                                                vertical: 8,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: isSelected
                                                                ? const Color(
                                                                    0xFF3390EC,
                                                                  ).withValues(
                                                                    alpha: 0.14,
                                                                  )
                                                                : (isFocused
                                                                      ? (isDark
                                                                          ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                                                                          : const Color(0xFFFEF3C7))
                                                                      : bubbleColor),
                                                            gradient:
                                                                !isSelected &&
                                                                    !isFocused &&
                                                                    isMine &&
                                                                    resolved
                                                                        .hasOutgoingGradient
                                                                ? LinearGradient(
                                                                    begin: Alignment
                                                                        .topLeft,
                                                                    end: Alignment
                                                                        .bottomRight,
                                                                    colors: resolved
                                                                        .outgoingBubbleColors,
                                                                  )
                                                                : null,
                                                            borderRadius: BorderRadius.only(
                                                              topLeft:
                                                                  const Radius.circular(
                                                                    18,
                                                                  ),
                                                              topRight:
                                                                  const Radius.circular(
                                                                    18,
                                                                  ),
                                                              bottomLeft:
                                                                  Radius.circular(
                                                                    isMine
                                                                        ? 18
                                                                        : 4,
                                                                  ),
                                                              bottomRight:
                                                                  Radius.circular(
                                                                    isMine
                                                                        ? 4
                                                                        : 18,
                                                                  ),
                                                            ),
                                                            border: isSelected
                                                                ? Border.all(
                                                                    color: const Color(
                                                                      0xFF3390EC,
                                                                    ),
                                                                    width: 1.5,
                                                                  )
                                                                : (isFocused
                                                                      ? Border.all(
                                                                          color: const Color(
                                                                            0xFFF59E0B,
                                                                          ),
                                                                          width: 1.5,
                                                                        )
                                                                      : (isMine
                                                                          ? null
                                                                          : Border.all(
                                                                              color: colorScheme
                                                                                  .outlineVariant
                                                                                  .withValues(
                                                                                    alpha: 0.25,
                                                                                  ),
                                                                              width: 0.5,
                                                                            ))),
                                                          ),
                                                          child: IntrinsicWidth(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .stretch,
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              if (!isMine &&
                                                                  _data.type !=
                                                                      'direct')
                                                                Padding(
                                                                  padding:
                                                                      const EdgeInsets.only(
                                                                        bottom:
                                                                            6,
                                                                      ),
                                                                  child: Text(
                                                                    message
                                                                            .sender
                                                                            ?.displayName ??
                                                                        'مستخدم',
                                                                    style: theme
                                                                        .textTheme
                                                                        .labelMedium
                                                                        ?.copyWith(
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                          color:
                                                                              resolved.accent,
                                                                        ),
                                                                  ),
                                                                ),
                                                              if (message
                                                                      .forwardedFromName !=
                                                                  null)
                                                                Padding(
                                                                  padding:
                                                                      const EdgeInsets.only(
                                                                        bottom:
                                                                            8,
                                                                      ),
                                                                  child: Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Icon(
                                                                        Icons
                                                                            .forward_rounded,
                                                                        size:
                                                                            15,
                                                                        color: resolved
                                                                            .accent,
                                                                      ),
                                                                      const SizedBox(
                                                                        width:
                                                                            6,
                                                                      ),
                                                                      Flexible(
                                                                        child: Text(
                                                                          'معاد توجيهها من ${message.forwardedFromName!}',
                                                                          maxLines:
                                                                              1,
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                          style: TextStyle(
                                                                            color:
                                                                                resolved.accent,
                                                                            fontSize:
                                                                                12,
                                                                            fontWeight:
                                                                                FontWeight.w700,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              if (_data.type == 'broadcast' &&
                                                                  (message.sentToAllDepartments ||
                                                                      message.broadcastTargetDepartmentNames.isNotEmpty ||
                                                                      message.broadcastTargetUserNames.isNotEmpty))
                                                                Builder(
                                                                  builder: (context) {
                                                                    final List<String> targets = [];
                                                                    if (message.broadcastTargetDepartmentNames.isNotEmpty) {
                                                                      targets.add(message.broadcastTargetDepartmentNames.join('، '));
                                                                    }
                                                                    if (message.broadcastTargetUserNames.isNotEmpty) {
                                                                      targets.add(message.broadcastTargetUserNames.join('، '));
                                                                    }
                                                                    final String targetText = message.sentToAllDepartments
                                                                        ? 'إرسال إلى كل الأقسام'
                                                                        : (targets.isNotEmpty
                                                                            ? 'إرسال إلى: ${targets.join(' • ')}'
                                                                            : 'إرسال إلى كل الأقسام');

                                                                    return Container(
                                                                      width: double.infinity,
                                                                      margin: const EdgeInsets.only(bottom: 8),
                                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                                                      decoration: BoxDecoration(
                                                                        color: const Color(0xFFE67E22).withValues(alpha: 0.1),
                                                                        borderRadius: BorderRadius.circular(12),
                                                                      ),
                                                                      child: Text(
                                                                        targetText,
                                                                        maxLines: 2,
                                                                        overflow: TextOverflow.ellipsis,
                                                                        style: const TextStyle(
                                                                          color: Color(0xFFB85714),
                                                                          fontWeight: FontWeight.w700,
                                                                          fontSize: 12,
                                                                        ),
                                                                      ),
                                                                    );
                                                                  },
                                                                ),
                                                              if (replyPreview !=
                                                                  null)
                                                                GestureDetector(
                                                                  behavior: HitTestBehavior.opaque,
                                                                  onTap: () {
                                                                    final replyId = message.replyToMessageId;
                                                                    if (replyId != null && replyId.isNotEmpty) {
                                                                      _jumpToRepliedMessage(replyId);
                                                                    }
                                                                  },
                                                                  child: Container(
                                                                    width: double
                                                                        .infinity,
                                                                    margin:
                                                                        const EdgeInsets.only(
                                                                          bottom:
                                                                              8,
                                                                        ),
                                                                    padding:
                                                                        const EdgeInsets.all(
                                                                          10,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color:
                                                                          replyBgColor,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            14,
                                                                          ),
                                                                    ),
                                                                    child: Column(
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children: [
                                                                        if (replyPreviewSender !=
                                                                            null)
                                                                          Padding(
                                                                            padding: const EdgeInsets.only(
                                                                              bottom:
                                                                                  3,
                                                                            ),
                                                                            child: Text(
                                                                              replyPreviewSender,
                                                                              maxLines:
                                                                                  1,
                                                                              overflow:
                                                                                  TextOverflow.ellipsis,
                                                                              style: TextStyle(
                                                                                color: resolved.accent,
                                                                                fontSize: 12,
                                                                                fontWeight: FontWeight.w700,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        Text(
                                                                          replyPreview,
                                                                          maxLines:
                                                                              2,
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                          style: TextStyle(
                                                                            color:
                                                                                subTextColor,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                              AnimatedSwitcher(
                                                                duration:
                                                                    const Duration(
                                                                      milliseconds:
                                                                          240,
                                                                    ),
                                                                switchInCurve:
                                                                    Curves
                                                                        .easeOutCubic,
                                                                switchOutCurve:
                                                                    Curves
                                                                        .easeInCubic,
                                                                transitionBuilder:
                                                                    (
                                                                      child,
                                                                      animation,
                                                                    ) {
                                                                      return FadeTransition(
                                                                        opacity:
                                                                            animation,
                                                                        child: SizeTransition(
                                                                          sizeFactor:
                                                                              animation,
                                                                          axisAlignment:
                                                                              -1,
                                                                          child:
                                                                              child,
                                                                        ),
                                                                      );
                                                                    },
                                                                child:
                                                                    message
                                                                        .isDeleted
                                                                    ? Container(
                                                                        key: ValueKey(
                                                                          'deleted_$stableItemKey',
                                                                        ),
                                                                        alignment:
                                                                            Alignment.centerLeft,
                                                                        child: Text(
                                                                          'تم حذف هذه الرسالة',
                                                                          style: TextStyle(
                                                                            color:
                                                                                subTextColor,
                                                                            fontStyle:
                                                                                FontStyle.italic,
                                                                          ),
                                                                        ),
                                                                      )
                                                                    : Column(
                                                                        key: ValueKey(
                                                                          'content_$stableItemKey',
                                                                        ),
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.stretch,
                                                                        mainAxisSize:
                                                                            MainAxisSize.min,
                                                                        children: [
                                                                          if (message
                                                                              .isPollMessage)
                                                                            ChatPollBubble(
                                                                              poll:
                                                                                  message.metadata?['poll']
                                                                                      is Map<
                                                                                        String,
                                                                                        dynamic
                                                                                      >
                                                                                  ? message.metadata!['poll']
                                                                                        as Map<
                                                                                          String,
                                                                                          dynamic
                                                                                        >
                                                                                  : message.metadata ??
                                                                                        {},
                                                                              currentUserId:
                                                                                  ref
                                                                                      .watch(
                                                                                        authControllerProvider,
                                                                                      )
                                                                                      .valueOrNull
                                                                                      ?.id ??
                                                                                  '',
                                                                              isMine: isMine,
                                                                              onVote:
                                                                                  (
                                                                                    optionIds,
                                                                                  ) => ref
                                                                                      .read(
                                                                                        conversationMessagesControllerProvider(
                                                                                          widget.conversation.id,
                                                                                        ).notifier,
                                                                                      )
                                                                                      .votePoll(
                                                                                        message.id,
                                                                                        optionIds,
                                                                                      ),
                                                                              onExport: () => ref
                                                                                  .read(
                                                                                    conversationMessagesControllerProvider(
                                                                                      widget.conversation.id,
                                                                                    ).notifier,
                                                                                  )
                                                                                  .exportPoll(
                                                                                    message.id,
                                                                                  ),
                                                                            )
                                                                          else if (message
                                                                              .isGifMessage)
                                                                            ClipRRect(
                                                                              borderRadius: BorderRadius.circular(
                                                                                14,
                                                                              ),
                                                                              child: Image.network(
                                                                                message.fileUrl ??
                                                                                    '',
                                                                                fit: BoxFit.cover,
                                                                              ),
                                                                            )
                                                                          else if (message
                                                                              .content
                                                                              .isNotEmpty)
                                                                            ChatLinkText(
                                                                              text: message.content,
                                                                              style: TextStyle(
                                                                                color: textColor,
                                                                                height: 1.45,
                                                                              ),
                                                                              textAlign: TextAlign.start,
                                                                            ),
                                                                          if (message
                                                                              .hasAttachment)
                                                                            Padding(
                                                                              padding: EdgeInsets.only(
                                                                                top: message.content.isNotEmpty ? 8 : 0,
                                                                              ),
                                                                              child: message.isAudioMessage
                                                                                  ? ChatAudioAttachmentPlayer(
                                                                                      message: message,
                                                                                      isMine: isMine,
                                                                                    )
                                                                                  : message.isImageMessage &&
                                                                                        albumMessages.length >
                                                                                            1
                                                                                  ? _ChatMediaAlbum(
                                                                                      messages: albumMessages,
                                                                                      width: maxBubbleWidth,
                                                                                      onOpen: _showImagePreview,
                                                                                    )
                                                                                  : message.isStickerMessage
                                                                                  ? InkWell(
                                                                                      onTap: _selectionMode
                                                                                          ? () => _toggleMessageSelection(message.id)
                                                                                          : () => _saveReceivedSticker(message),
                                                                                      onDoubleTap: () => _handleDoubleTapReaction(message),
                                                                                      onLongPress: _selectionMode
                                                                                          ? () => _toggleMessageSelection(message.id)
                                                                                          : () => _showWhatsAppContextMenu(message),
                                                                                      borderRadius: BorderRadius.circular(14),
                                                                                      child: Stack(
                                                                                        children: [
                                                                                          Container(
                                                                                            padding: const EdgeInsets.all(4),
                                                                                            constraints: const BoxConstraints(
                                                                                              maxWidth: 170,
                                                                                              maxHeight: 170,
                                                                                            ),
                                                                                                                                                                                          child: _ChatAttachmentImage(
                                                                                                message: message,
                                                                                                fit: BoxFit.contain,
                                                                                              ),
                                                                                          ),
                                                                                          Positioned(
                                                                                            bottom: 2,
                                                                                            left: 2,
                                                                                            child: InkWell(
                                                                                              onTap: () => _saveReceivedSticker(message),
                                                                                              borderRadius: BorderRadius.circular(12),
                                                                                              child: Container(
                                                                                                padding: const EdgeInsets.symmetric(
                                                                                                  horizontal: 6,
                                                                                                  vertical: 3,
                                                                                                ),
                                                                                                decoration: BoxDecoration(
                                                                                                  color: (isDark ? const Color(0xFF1C1C1E) : Colors.white).withValues(alpha: 0.92),
                                                                                                  borderRadius: BorderRadius.circular(12),
                                                                                                  border: Border.all(
                                                                                                    color: isDark ? const Color(0xFF38383E) : const Color(0xFFE2E8F0),
                                                                                                    width: 0.8,
                                                                                                  ),
                                                                                                  boxShadow: [
                                                                                                    BoxShadow(
                                                                                                      color: Colors.black.withValues(alpha: 0.12),
                                                                                                      blurRadius: 4,
                                                                                                      offset: const Offset(0, 1),
                                                                                                    ),
                                                                                                  ],
                                                                                                ),
                                                                                                child: Row(
                                                                                                  mainAxisSize: MainAxisSize.min,
                                                                                                  children: [
                                                                                                    const Icon(
                                                                                                      Icons.auto_awesome_motion_rounded,
                                                                                                      size: 11,
                                                                                                      color: Color(0xFF007AFF),
                                                                                                    ),
                                                                                                    const SizedBox(width: 3),
                                                                                                    Text(
                                                                                                      'حفظ كملصق',
                                                                                                      style: TextStyle(
                                                                                                        fontSize: 9.5,
                                                                                                        fontWeight: FontWeight.w700,
                                                                                                        color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                                                                                                      ),
                                                                                                    ),
                                                                                                  ],
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ],
                                                                                      ),
                                                                                    )
                                                                                  : message.isImageMessage
                                                                                  ? InkWell(
                                                                                      onTap: _selectionMode
                                                                                          ? () => _toggleMessageSelection(message.id)
                                                                                          : () => _openAttachment(message),
                                                                                      onDoubleTap: () => _handleDoubleTapReaction(message),
                                                                                      onLongPress: _selectionMode
                                                                                          ? () => _toggleMessageSelection(message.id)
                                                                                          : (message.isStickerMessage
                                                                                              ? () => _saveReceivedSticker(message)
                                                                                              : () => _showWhatsAppContextMenu(message)),
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        14,
                                                                                      ),
                                                                                      child: ClipRRect(
                                                                                        borderRadius: BorderRadius.circular(
                                                                                          14,
                                                                                        ),
                                                                                        child: SizedBox(
                                                                                          width: maxBubbleWidth,
                                                                                          height: 180,
                                                                                          child: Hero(
                                                                                            tag: 'image_$stableItemKey',
                                                                                            child: _ChatAttachmentImage(
                                                                                              message: message,
                                                                                              fit: BoxFit.cover,
                                                                                              height: 180,
                                                                                              width: maxBubbleWidth,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    )
                                                                                  : Builder(
                                                                                      builder: (context) {
                                                                                        final isAttachmentDownloaded =
                                                                                            _cachedAttachmentIds.contains(message.id) ||
                                                                                            isMine ||
                                                                                            (message.metadata?['localPath'] != null &&
                                                                                                File(message.metadata!['localPath'].toString()).existsSync());
                                                                                        if (message.hasAttachment && !_checkedAttachmentIds.contains(message.id)) {
                                                                                          _checkSingleAttachmentCached(message);
                                                                                        }
                                                                                        return InkWell(
                                                                                          onTap: _selectionMode
                                                                                              ? () => _toggleMessageSelection(message.id)
                                                                                              : () => _openAttachment(message),
                                                                                          onDoubleTap: () => _handleDoubleTapReaction(message),
                                                                                          onLongPress: () {
                                                                                            if (_selectionMode) {
                                                                                              _toggleMessageSelection(message.id);
                                                                                            } else {
                                                                                              _showWhatsAppContextMenu(message);
                                                                                            }
                                                                                          },
                                                                                          borderRadius: BorderRadius.circular(14),
                                                                                          child: Container(
                                                                                            width: double.infinity,
                                                                                            padding: const EdgeInsets.all(10),
                                                                                            decoration: BoxDecoration(
                                                                                              color: replyBgColor,
                                                                                              borderRadius: BorderRadius.circular(14),
                                                                                            ),
                                                                                            child: Row(
                                                                                              children: [
                                                                                                Icon(
                                                                                                  _attachmentIcon(message.messageType),
                                                                                                  color: isAttachmentDownloaded
                                                                                                      ? const Color(0xFF10B981)
                                                                                                      : textColor,
                                                                                                ),
                                                                                                const SizedBox(width: 8),
                                                                                                Flexible(
                                                                                                  child: Column(
                                                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                                                    mainAxisSize: MainAxisSize.min,
                                                                                                    children: [
                                                                                                      Text(
                                                                                                        message.fileName ?? 'ملف مرفق',
                                                                                                        maxLines: 1,
                                                                                                        overflow: TextOverflow.ellipsis,
                                                                                                        style: TextStyle(
                                                                                                          color: textColor,
                                                                                                          fontWeight: FontWeight.w600,
                                                                                                          fontSize: 13,
                                                                                                        ),
                                                                                                      ),
                                                                                                      const SizedBox(height: 2),
                                                                                                      Text(
                                                                                                        message.fileSize != null && message.fileSize! > 0
                                                                                                            ? '${formatFileSize(message.fileSize!)}${isAttachmentDownloaded ? " • تم التنزيل" : ""}'
                                                                                                            : (isAttachmentDownloaded ? 'تم التنزيل' : 'انقر للتنزيل'),
                                                                                                        style: TextStyle(
                                                                                                          color: subTextColor,
                                                                                                          fontSize: 11,
                                                                                                        ),
                                                                                                      ),
                                                                                                    ],
                                                                                                  ),
                                                                                                ),
                                                                                                if (message.isPrintableAttachment)
                                                                                                  IconButton(
                                                                                                    visualDensity: VisualDensity.compact,
                                                                                                    onPressed: () => _requestAttachmentPrint(message),
                                                                                                    icon: Icon(
                                                                                                      Icons.print_rounded,
                                                                                                      size: 18,
                                                                                                      color: subTextColor,
                                                                                                    ),
                                                                                                  ),
                                                                                                if (_downloadStates.containsKey(message.id))
                                                                                                  SizedBox(
                                                                                                    width: 20,
                                                                                                    height: 20,
                                                                                                    child: CircularProgressIndicator(
                                                                                                      value: _downloadStates[message.id]!.progress > 0
                                                                                                          ? _downloadStates[message.id]!.progress
                                                                                                          : null,
                                                                                                      strokeWidth: 2,
                                                                                                      color: subTextColor,
                                                                                                    ),
                                                                                                  )
                                                                                                else if (isAttachmentDownloaded)
                                                                                                  Icon(
                                                                                                    Icons.open_in_new_rounded,
                                                                                                    size: 19,
                                                                                                    color: subTextColor,
                                                                                                  )
                                                                                                else
                                                                                                  Icon(
                                                                                                    message.attachmentDownloadAllowed
                                                                                                        ? Icons.download_rounded
                                                                                                        : Icons.lock_rounded,
                                                                                                    size: 19,
                                                                                                    color: subTextColor,
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
                                                              ),
                                                              const SizedBox(
                                                                height: 3,
                                                              ),
                                                              Align(
                                                                alignment: AlignmentDirectional.bottomEnd,
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    if (message.isAttachmentViewOnly ||
                                                                        !message.attachmentForwardAllowed ||
                                                                        message.metadata?['allowForward'] == false) ...[
                                                                      const Tooltip(
                                                                        message: 'محتوى محمي: غير مسموح بإعادة التوجيه',
                                                                        child: Icon(
                                                                          Icons.lock_rounded,
                                                                          size: 11.5,
                                                                          color: Color(0xFF10B981),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(width: 3),
                                                                    ],
                                                                    if (isFavorited) ...[
                                                                        const Icon(
                                                                          Icons.star_rounded,
                                                                          size: 13,
                                                                          color: Color(0xFFF59E0B),
                                                                        ),
                                                                        const SizedBox(
                                                                          width: 3,
                                                                        ),
                                                                      ],
                                                                      Text(
                                                                      formatEgyptTime(
                                                                        messageLocalDate,
                                                                      ),
                                                                      style: TextStyle(
                                                                        color:
                                                                            subTextColor,
                                                                        fontSize:
                                                                            11,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                    ),
                                                                    if (message
                                                                        .isEdited) ...[
                                                                      const SizedBox(
                                                                        width: 4,
                                                                      ),
                                                                      Text(
                                                                        'معدلة',
                                                                        style: TextStyle(
                                                                          color:
                                                                              subTextColor,
                                                                          fontSize:
                                                                              11,
                                                                          fontWeight:
                                                                              FontWeight.w500,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                    if (status !=
                                                                        null) ...[
                                                                      const SizedBox(
                                                                        width: 4,
                                                                      ),
                                                                      if (message.isFailed)
                                                                        GestureDetector(
                                                                          onTap: () => _showActions(message),
                                                                          child: Icon(
                                                                            status.icon,
                                                                            size: 15,
                                                                            color: status.color,
                                                                          ),
                                                                        )
                                                                      else
                                                                        AnimatedSwitcher(
                                                                          duration: const Duration(milliseconds: 220),
                                                                          transitionBuilder: (child, animation) => ScaleTransition(
                                                                            scale: CurvedAnimation(
                                                                              parent: animation,
                                                                              curve: Curves.easeOutBack,
                                                                            ),
                                                                            child: child,
                                                                          ),
                                                                          child: Icon(
                                                                            status.icon,
                                                                            key: ValueKey(status.icon),
                                                                            size: 15,
                                                                            color: status.color,
                                                                          ),
                                                                        ),
                                                                    ],
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                      if (_sortedReactionEntries(
                                                        message,
                                                      ).isNotEmpty)
                                                        Transform.translate(
                                                          offset: const Offset(
                                                            0,
                                                            -12,
                                                          ),
                                                          child: Padding(
                                                            padding:
                                                                EdgeInsets.only(
                                                                  left: isMine
                                                                      ? 34
                                                                      : 0,
                                                                  right: isMine
                                                                      ? 0
                                                                      : 34,
                                                                  bottom: 2,
                                                                ),
                                                            child: _ReactionWrap(
                                                              message: message,
                                                              currentUserId:
                                                                  authUser?.id,
                                                              isMine: isMine,
                                                              isDark: isDark,
                                                              onToggle: (emoji) => ref
                                                                  .read(
                                                                    conversationMessagesControllerProvider(
                                                                      widget
                                                                          .conversation
                                                                          .id,
                                                                    ).notifier,
                                                                  )
                                                                  .toggleReaction(
                                                                    messageId:
                                                                        message
                                                                            .id,
                                                                    emoji:
                                                                        emoji,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                   if (_pulsingHeartMessageId == message.id)
                                                     Positioned.fill(
                                                       child: Center(
                                                         child: TweenAnimationBuilder<double>(
                                                           tween: Tween(begin: 0.0, end: 1.0),
                                                           duration: const Duration(milliseconds: 650),
                                                           curve: Curves.elasticOut,
                                                           builder: (context, val, child) {
                                                             final scale = val <= 0.6
                                                                 ? (val / 0.6 * 1.35)
                                                                 : (1.35 - ((val - 0.6) / 0.4 * 0.35));
                                                             final opacity = (1.0 - (val > 0.7 ? (val - 0.7) / 0.3 : 0.0)).clamp(0.0, 1.0);
                                                             return Opacity(
                                                               opacity: opacity,
                                                               child: Transform.scale(
                                                                 scale: scale,
                                                                 child: const Icon(
                                                                   CupertinoIcons.heart_fill,
                                                                   color: Color(0xFFE53935),
                                                                   size: 52,
                                                                   shadows: [
                                                                     BoxShadow(
                                                                       color: Colors.black26,
                                                                       blurRadius: 10,
                                                                       offset: Offset(0, 3),
                                                                     ),
                                                                   ],
                                                                 ),
                                                               ),
                                                             );
                                                           },
                                                         ),
                                                       ),
                                                     ),
                                                  if (_selectionMode)
                                                    Positioned(
                                                      top: -2,
                                                      left: isMine ? -4 : null,
                                                      right: isMine ? null : -4,
                                                      child: AnimatedScale(
                                                        duration:
                                                            const Duration(
                                                              milliseconds: 140,
                                                            ),
                                                        scale: isSelected
                                                            ? 1
                                                            : 0.9,
                                                        child: Icon(
                                                          isSelected
                                                              ? Icons
                                                                    .check_circle_rounded
                                                              : Icons
                                                                    .radio_button_unchecked_rounded,
                                                          color: isSelected
                                                              ? const Color(
                                                                  0xFF3390EC,
                                                                )
                                                              : const Color(
                                                                  0xFF9AA7B4,
                                                                ),
                                                          size: 22,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (!isMine && isLastInGroup)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 8,
                                                bottom: 2,
                                              ),
                                              child: Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: resolved.accent
                                                      .withValues(alpha: 0.18),
                                                  shape: BoxShape.circle,
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child:
                                                    message
                                                            .sender
                                                            ?.avatarUrl
                                                            ?.isNotEmpty ==
                                                        true
                                                    ? CachedNetworkImage(
                                                        imageUrl:
                                                            resolveMediaUrl(
                                                              message
                                                                  .sender!
                                                                  .avatarUrl!,
                                                            )!,
                                                        httpHeaders:
                                                            token != null &&
                                                                token.isNotEmpty
                                                            ? {
                                                                'Authorization':
                                                                    'Bearer $token',
                                                              }
                                                            : null,
                                                        fit: BoxFit.cover,
                                                        placeholder:
                                                            (
                                                              context,
                                                              url,
                                                            ) => Center(
                                                              child: Text(
                                                                senderName
                                                                        .isEmpty
                                                                    ? '?'
                                                                    : senderName[0]
                                                                          .toUpperCase(),
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: resolved
                                                                      .accent,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                        errorWidget:
                                                            (
                                                              context,
                                                              url,
                                                              error,
                                                            ) => Center(
                                                              child: Text(
                                                                senderName
                                                                        .isEmpty
                                                                    ? '?'
                                                                    : senderName[0]
                                                                          .toUpperCase(),
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: resolved
                                                                      .accent,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                      )
                                                    : Center(
                                                        child: Text(
                                                          senderName.isEmpty
                                                              ? '?'
                                                              : senderName[0]
                                                                    .toUpperCase(),
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                resolved.accent,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                              ),
                                            )
                                          else if (!isMine && !isLastInGroup)
                                            const SizedBox(width: 36),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );

                          final animationKey =
                              message.metadata?['clientMessageId']?.toString() ??
                              message.id;
                          final alreadyAnimated =
                              _animatedMessageIds.contains(animationKey) ||
                              _animatedMessageIds.contains(message.id);

                          if (!alreadyAnimated) {
                            _animatedMessageIds.add(animationKey);
                            _animatedMessageIds.add(message.id);
                            child = child
                                .animate()
                                .fade(duration: 200.ms)
                                .slideY(
                                  begin: 0.2,
                                  end: 0,
                                  duration: 200.ms,
                                  curve: Curves.easeOut,
                                );
                          } else {
                            _animatedMessageIds.add(animationKey);
                            _animatedMessageIds.add(message.id);
                          }
                          return child;
                        },
                      );
                    },
                  ),
                ),
                if (_replyingTo != null || _editingMessage != null)
                  _ComposerBanner(
                    colorScheme: colorScheme,
                    isEditing: _editingMessage != null,
                    text: _editingMessage != null
                        ? _editingMessage!.content
                        : (_replyingTo!.content.isNotEmpty
                              ? _replyingTo!.content
                              : (_replyingTo!.fileName ?? 'ملف مرفق')),
                    onClose: () => setState(() {
                      _replyingTo = null;
                      _editingMessage = null;
                    }),
                  ),
                if (_downloadStates.isNotEmpty)
                  Column(
                    children: _downloadStates.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _DownloadBanner(
                          key: ValueKey(entry.key),
                          colorScheme: colorScheme,
                          fileName: entry.value.fileName,
                          progress: entry.value.progress,
                        ),
                      );
                    }).toList(),
                  ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: typingIndicatorText == null
                      ? const SizedBox.shrink()
                      : _TypingIndicatorBubble(
                          key: ValueKey(typingIndicatorText),
                          colorScheme: colorScheme,
                          text: typingIndicatorText,
                        ),
                ),
                if (_mentionQuery != null && _mentionResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: _mentionResults.length,
                      itemBuilder: (context, index) {
                        final user = _mentionResults[index];
                        return ListTile(
                          leading: ChatAvatar(
                            avatarUrl: user.avatarUrl,
                            radius: 16,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            fallback: Text(
                              user.displayName.isNotEmpty
                                  ? user.displayName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '@${user.username}',
                            maxLines: 1,
                            style: const TextStyle(fontSize: 12),
                          ),
                          onTap: () => _insertMention(user),
                        );
                      },
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: _MessageComposer(
                    controller: _messageController,
                    colorScheme: colorScheme,
                    enabled: !isReadOnly,
                    isEditing: _editingMessage != null,
                    isUploading: _isUploadingAttachment,
                    uploadFileName: _uploadingFileName,
                    uploadProgress: _uploadProgress,
                    enterSendsMessage: enterSendsMessage,
                    onAttach: _sendFile,
                    onPickImage: _sendImages,
                    onTakePhoto: _takePhotoAndSend,
                    onSendSpecificFile: _sendSpecificFile,
                    onSendScreenshot: _sendScreenshotFromDevice,
                    onOpenReactionPicker: _showComposerReactionPicker,
                    onSendPoll: _createPoll,
                    onSendChecklist: _createChecklist,
                    onOpenEmojiPicker: _openEmojiPicker,
                    onSendGif: _openGifPicker,
                    onPauseVoiceNote: _pauseVoiceRecording,
                    onResumeVoiceNote: _resumeVoiceRecording,
                    onStopVoiceNote: _stopVoiceRecordingKeepDraft,
                    onVoiceLongPressStart: _handleVoiceMicLongPressStart,
                    onVoiceLongPressMove: _handleVoiceMicLongPressMove,
                    onVoiceLongPressEnd: _handleVoiceMicLongPressEnd,
                    onSendVoiceNote: _voiceDraftPath != null
                        ? _sendVoiceDraft
                        : _stopAndSendVoiceNote,
                    onCancelVoiceNote: _voiceDraftPath != null
                        ? _deleteVoiceDraft
                        : _cancelVoiceRecording,
                    onSend: _sendText,
                    onSendOptions: _showSendOptions,
                    isRecordingVoice: _isRecordingVoice,
                    isVoiceHoldActive: _isVoiceHoldActive,
                    isVoiceLocked: _isVoiceRecordingLocked,
                    voiceSlideCancelArmed: _voiceSlideCancelArmed,
                    voiceGestureOffset: _voiceGestureOffset,
                    recordingDuration: _recordingDuration,
                    isVoicePaused: _isVoiceRecordingPaused,
                    hasVoiceDraft: _voiceDraftPath != null,
                    onChanged: (value) {
                      if (isReadOnly) {
                        return;
                      }
                      if (value.trim().isEmpty) {
                        if (_didSendTyping) {
                          ref
                              .read(
                                conversationMessagesControllerProvider(
                                  widget.conversation.id,
                                ).notifier,
                              )
                              .stopTyping();
                          _didSendTyping = false;
                        }
                        return;
                      }

                      _scheduleStopTyping();
                    },
                  ),
                ),
              ],
            ),
            PositionedDirectional(
              end: 16,
              bottom: 96 + MediaQuery.paddingOf(context).bottom,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                offset: _showScrollToLatestButton
                    ? Offset.zero
                    : const Offset(0, 0.8),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _showScrollToLatestButton ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_showScrollToLatestButton,
                    child: Badge(
                      isLabelVisible: _unreadBelowCount > 0,
                      label: Text('$_unreadBelowCount'),
                      child: FloatingActionButton.small(
                        heroTag: 'scroll_to_latest_btn',
                        tooltip: 'آخر رسالة',
                        onPressed: () => _scrollToBottom(animated: true),
                        child: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
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

class _MessageStatus {
  const _MessageStatus(this.icon, this.color);

  final IconData icon;
  final Color color;
}

class _SheetCountChip extends StatelessWidget {
  const _SheetCountChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SheetEmptyState extends StatelessWidget {
  const _SheetEmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ChatAttachmentImage extends ConsumerStatefulWidget {
  const _ChatAttachmentImage({
    required this.message,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final ChatMessage message;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  ConsumerState<_ChatAttachmentImage> createState() =>
      _ChatAttachmentImageState();
}

class _ChatAttachmentImageState extends ConsumerState<_ChatAttachmentImage> {
  late Future<Uint8List> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _ChatAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.updatedAt != widget.message.updatedAt) {
      _bytesFuture = _loadBytes();
    }
  }

  Future<Uint8List> _loadBytes() {
    return ref
        .read(chatRepositoryProvider)
        .fetchAttachmentPreviewBytes(widget.message);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget errorWidget() => Container(
      height: widget.height,
      width: widget.width,
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, size: 30),
    );

    return FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return AppMediaLoadingPlaceholder(
            height: widget.height ?? 200,
            width: widget.width ?? double.infinity,
            borderRadius: 16,
          );
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return errorWidget();
        }
        if (_isSvgMessage(widget.message, bytes)) {
          return SvgPicture.memory(
            bytes,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            placeholderBuilder: (_) => AppMediaLoadingPlaceholder(
              height: widget.height ?? 200,
              width: widget.width ?? double.infinity,
              borderRadius: 16,
            ),
          );
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => errorWidget(),
        );
      },
    );
  }

  bool _isSvgMessage(ChatMessage message, Uint8List bytes) {
    final mime = message.mimeType?.toLowerCase().trim() ?? '';
    final name = message.fileName?.toLowerCase().trim() ?? '';
    if (mime == 'image/svg+xml' || name.endsWith('.svg')) {
      return true;
    }
    final sample = String.fromCharCodes(bytes.take(256)).toLowerCase();
    return sample.contains('<svg');
  }
}

class _ChatMessagesLoadingSkeleton extends StatelessWidget {
  const _ChatMessagesLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: const [
        Align(
          alignment: Alignment.center,
          child: ShimmerSkeleton(width: 112, height: 22, borderRadius: 12),
        ),
        SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerSkeleton(width: 64, height: 12, borderRadius: 999),
        ),
        SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerSkeleton(width: 220, height: 84, borderRadius: 18),
        ),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ShimmerSkeleton(width: 190, height: 64, borderRadius: 18),
        ),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: ShimmerSkeleton(width: 248, height: 76, borderRadius: 18),
        ),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: ShimmerSkeleton(width: 164, height: 56, borderRadius: 18),
        ),
      ],
    );
  }
}


class _ChatMediaAlbum extends StatelessWidget {
  const _ChatMediaAlbum({
    required this.messages,
    required this.width,
    required this.onOpen,
  });
  final List<ChatMessage> messages;
  final double width;
  final ValueChanged<ChatMessage> onOpen;

  Widget _buildImage(ChatMessage message, [int? overflowCount]) {
    return InkWell(
      onTap: () => onOpen(message),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'image_${message.id}',
            child: _ChatAttachmentImage(message: message, fit: BoxFit.cover),
          ),
          if (overflowCount != null)
            ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Text(
                  '+$overflowCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = messages.length;
    if (count == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: width, height: 240, child: _buildLayout()),
    );
  }

  Widget _buildLayout() {
    final count = messages.length;

    if (count == 1) {
      return _buildImage(messages[0]);
    }

    if (count == 2) {
      return Row(
        children: [
          Expanded(child: _buildImage(messages[0])),
          const SizedBox(width: 2),
          Expanded(child: _buildImage(messages[1])),
        ],
      );
    }

    if (count == 3) {
      return Column(
        children: [
          Expanded(flex: 2, child: _buildImage(messages[0])),
          const SizedBox(height: 2),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Expanded(child: _buildImage(messages[1])),
                const SizedBox(width: 2),
                Expanded(child: _buildImage(messages[2])),
              ],
            ),
          ),
        ],
      );
    }

    final overflow = count > 4 ? count - 4 : null;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildImage(messages[0])),
              const SizedBox(width: 2),
              Expanded(child: _buildImage(messages[1])),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildImage(messages[2])),
              const SizedBox(width: 2),
              Expanded(child: _buildImage(messages[3], overflow)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReactionWrap extends StatelessWidget {
  const _ReactionWrap({
    required this.message,
    required this.currentUserId,
    required this.isMine,
    required this.isDark,
    required this.onToggle,
  });

  final ChatMessage message;
  final String? currentUserId;
  final bool isMine;
  final bool isDark;
  final Future<void> Function(String emoji) onToggle;

  @override
  Widget build(BuildContext context) {
    final reactions = _sortedReactionEntries(message);
    if (reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 3,
      runSpacing: 4,
      alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < reactions.length; i++)
          _AnimatedReactionChip(
            emoji: reactions[i].key,
            count: reactions[i].value.length,
            selected: _reactionHasUser(reactions[i].value, currentUserId),
            isMine: isMine,
            isDark: isDark,
            staggerIndex: i,
            onTap: () => onToggle(reactions[i].key),
          ),
      ],
    );
  }
}

class _AnimatedReactionChip extends StatefulWidget {
  const _AnimatedReactionChip({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.isMine,
    required this.isDark,
    required this.staggerIndex,
    required this.onTap,
  });

  final String emoji;
  final int count;
  final bool selected;
  final bool isMine;
  final bool isDark;

  /// تأخير بسيط بين كل رياكت (تسلسل مثل تيليجرام).
  final int staggerIndex;
  final VoidCallback onTap;

  @override
  State<_AnimatedReactionChip> createState() => _AnimatedReactionChipState();
}

class _AnimatedReactionChipState extends State<_AnimatedReactionChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tapController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 120),
  );
  late final Animation<double> _tapScale = Tween<double>(
    begin: 1.0,
    end: 0.94,
  ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeOut));

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _handleTap() {
    unawaited(
      _tapController.forward(from: 0).then((_) => _tapController.reverse()),
    );
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.selected
        ? (widget.isDark
              ? const Color(0xFF2B5278).withValues(alpha: 0.85)
              : const Color(0xFFD8EAFD))
        : (widget.isDark
              ? const Color(0xFF2A3441).withValues(alpha: 0.92)
              : const Color(0xFFF8FAFC));
    final borderColor = widget.selected
        ? const Color(0xFF3390EC)
        : (widget.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0));
    final emojiStyle = TextStyle(
      fontSize: 17,
      height: 1.05,
      fontFamilyFallback: _kChatReactionEmojiFontFallbacks,
    );

    return ScaleTransition(
      scale: _tapScale,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.isDark ? 0.22 : 0.05,
                ),
                blurRadius: widget.selected ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.emoji, style: emojiStyle),
              const SizedBox(width: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Text(
                  '${widget.count}',
                  key: ValueKey(widget.count),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.selected
                        ? const Color(0xFF3390EC)
                        : (widget.isDark
                              ? const Color(0xFFB8C7D6)
                              : const Color(0xFF64748B)),
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

class _TypingIndicatorBubble extends StatefulWidget {
  const _TypingIndicatorBubble({
    required this.colorScheme,
    required this.text,
    super.key,
  });

  final ColorScheme colorScheme;
  final String text;

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(
              color: widget.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  return Row(
                    children: List.generate(3, (index) {
                      final wave = math.sin((t * math.pi * 2) - (index * 0.55));
                      final opacity = (0.38 + ((wave + 1) * 0.26)).clamp(
                        0.24,
                        0.9,
                      );
                      return Container(
                        width: 6,
                        height: 6,
                        margin: EdgeInsetsDirectional.only(
                          end: index == 2 ? 0 : 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF3390EC,
                          ).withValues(alpha: opacity),
                          shape: BoxShape.circle,
                        ),
                      );
                    }),
                  );
                },
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
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

class _ComposerBanner extends StatelessWidget {
  const _ComposerBanner({
    required this.colorScheme,
    required this.isEditing,
    required this.text,
    required this.onClose,
  });

  final ColorScheme colorScheme;
  final bool isEditing;
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accent = isEditing
        ? const Color(0xFF4DCC6E)
        : const Color(0xFF3390EC);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 38,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing ? 'تعديل الرسالة' : 'رد على رسالة',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }
}

class _MessageDownloadState {
  const _MessageDownloadState({required this.fileName, required this.progress});
  final String fileName;
  final double progress;
}

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({
    super.key,
    required this.colorScheme,
    required this.fileName,
    required this.progress,
  });

  final ColorScheme colorScheme;
  final String fileName;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress >= -1) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppDownloadProgressBanner(
          fileName: fileName,
          progress: progress,
        ),
      );
    }
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.download_rounded, color: Color(0xFF19A974)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'جاري تنزيل $fileName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress <= 0 ? null : progress,
              color: const Color(0xFF19A974),
            ),
          ),
        ],
      ),
    );
  }
}

class _TelegramComposerUploadStrip extends StatelessWidget {
  const _TelegramComposerUploadStrip({
    required this.colorScheme,
    required this.fileName,
    required this.progress,
  });

  final ColorScheme colorScheme;
  final String fileName;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    final track = colorScheme.surfaceContainerHighest;
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  value: progress <= 0 ? null : progress,
                  color: const Color(0xFF3390EC),
                  backgroundColor: track,
                ),
              ),
              Icon(
                Icons.upload_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: progress <= 0 ? null : progress,
                  backgroundColor: track,
                  color: const Color(0xFF3390EC),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$pct%',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _VoiceHoldRecordingBar extends StatefulWidget {
  const _VoiceHoldRecordingBar({
    required this.colorScheme,
    required this.durationLabel,
    required this.slideCancelArmed,
    required this.gestureOffset,
    required this.isDark,
    required this.onCancel,
  });

  final ColorScheme colorScheme;
  final String durationLabel;
  final bool slideCancelArmed;
  final Offset gestureOffset;
  final bool isDark;
  final VoidCallback onCancel;

  @override
  State<_VoiceHoldRecordingBar> createState() => _VoiceHoldRecordingBarState();
}

class _VoiceHoldRecordingBarState extends State<_VoiceHoldRecordingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dragX = (widget.gestureOffset.dx * 0.35).clamp(-60.0, 60.0);

    final cancelColor = widget.slideCancelArmed
        ? const Color(0xFFEF4444)
        : (widget.isDark ? Colors.white70 : const Color(0xFF64748B));

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          // Explicit Clickable Cancel Button (Trash Icon + Text) - Guarantees the user can always tap to cancel!
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 17,
                      color: Color(0xFFEF4444),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'إلغاء',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 1. Red Pulsing Recording Indicator Dot
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final opacity = 0.35 + (_pulseController.value * 0.65);
              return Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: opacity),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: opacity * 0.6),
                      blurRadius: 5,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 6),

          // 2. Live Duration Counter
          Text(
            widget.durationLabel,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 10),

          // 3. Slide to Cancel Animated Indicator
          Expanded(
            child: Transform.translate(
              offset: Offset(dragX, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.slideCancelArmed
                        ? Icons.delete_forever_rounded
                        : Icons.chevron_right_rounded,
                    size: 18,
                    color: cancelColor,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      widget.slideCancelArmed ? 'اترك للإلغاء' : 'اسحب للإلغاء',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cancelColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating lock capsule displayed vertically above the mic button during hold-recording.
class _VoiceLockPill extends StatefulWidget {
  const _VoiceLockPill({
    required this.gestureDy,
    required this.isDark,
    required this.colorScheme,
  });

  final double gestureDy;
  final bool isDark;
  final ColorScheme colorScheme;

  @override
  State<_VoiceLockPill> createState() => _VoiceLockPillState();
}

class _VoiceLockPillState extends State<_VoiceLockPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNearLock = widget.gestureDy < -45;
    final dyOffset = (widget.gestureDy * 0.25).clamp(-20.0, 0.0);

    return Transform.translate(
      offset: Offset(0, dyOffset),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final bounce = math.sin(_anim.value * math.pi) * 3;
          return Container(
            width: 42,
            height: 84,
            decoration: BoxDecoration(
              color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isNearLock
                    ? const Color(0xFF00A884)
                    : (widget.isDark ? Colors.white12 : Colors.black12),
                width: isNearLock ? 1.5 : 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isNearLock
                        ? const Color(0xFF00A884).withValues(alpha: 0.15)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isNearLock ? Icons.lock_open_rounded : Icons.lock_rounded,
                    size: 20,
                    color: isNearLock
                        ? const Color(0xFF00A884)
                        : (widget.isDark ? Colors.white70 : const Color(0xFF64748B)),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -bounce),
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: isNearLock
                        ? const Color(0xFF00A884)
                        : (widget.isDark ? Colors.white38 : const Color(0xFF94A3B8)),
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

class _MessageComposer extends StatefulWidget {
  const _MessageComposer({
    required this.controller,
    required this.colorScheme,
    required this.enabled,
    required this.isEditing,
    required this.isUploading,
    required this.uploadFileName,
    required this.uploadProgress,
    required this.enterSendsMessage,
    required this.onAttach,
    required this.onPickImage,
    required this.onTakePhoto,
    this.onSendSpecificFile,
    required this.onSendScreenshot,
    required this.onOpenReactionPicker,
    required this.onSendPoll,
    required this.onSendChecklist,
    this.onOpenEmojiPicker,
    required this.onSendGif,
    required this.onPauseVoiceNote,
    required this.onResumeVoiceNote,
    required this.onStopVoiceNote,
    required this.onVoiceLongPressStart,
    required this.onVoiceLongPressMove,
    required this.onVoiceLongPressEnd,
    required this.onSendVoiceNote,
    required this.onCancelVoiceNote,
    required this.onSend,
    required this.onSendOptions,
    required this.isRecordingVoice,
    required this.isVoiceHoldActive,
    required this.isVoiceLocked,
    required this.voiceSlideCancelArmed,
    required this.voiceGestureOffset,
    required this.recordingDuration,
    required this.isVoicePaused,
    required this.hasVoiceDraft,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ColorScheme colorScheme;
  final bool enabled;
  final bool isEditing;
  final bool isUploading;
  final String? uploadFileName;
  final double uploadProgress;
  final bool enterSendsMessage;
  final VoidCallback onAttach;
  final VoidCallback onPickImage;
  final VoidCallback onTakePhoto;
  final ValueChanged<String>? onSendSpecificFile;
  final VoidCallback onSendScreenshot;
  final VoidCallback onOpenReactionPicker;
  final VoidCallback onSendPoll;
  final VoidCallback onSendChecklist;
  final VoidCallback? onOpenEmojiPicker;
  final VoidCallback onSendGif;
  final VoidCallback onPauseVoiceNote;
  final VoidCallback onResumeVoiceNote;
  final VoidCallback onStopVoiceNote;
  final Future<void> Function() onVoiceLongPressStart;
  final void Function(LongPressMoveUpdateDetails details) onVoiceLongPressMove;
  final Future<void> Function() onVoiceLongPressEnd;
  final VoidCallback onSendVoiceNote;
  final VoidCallback onCancelVoiceNote;
  final VoidCallback onSend;
  final VoidCallback onSendOptions;
  final bool isRecordingVoice;
  final bool isVoiceHoldActive;
  final bool isVoiceLocked;
  final bool voiceSlideCancelArmed;
  final Offset voiceGestureOffset;
  final Duration recordingDuration;
  final bool isVoicePaused;
  final bool hasVoiceDraft;
  final ValueChanged<String> onChanged;

  @override
  State<_MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<_MessageComposer> {
  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _openActionsMenu() async {
    if (!widget.enabled) return;

    final selected = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AttachmentBottomSheet(),
    );

    if (selected is String) {
      widget.onSendSpecificFile?.call(selected);
    }

    if (selected is AttachmentBottomSheetResult) {
      switch (selected) {
        case AttachmentBottomSheetResult.image:
          widget.onPickImage();
          break;
        case AttachmentBottomSheetResult.file:
          widget.onAttach();
          break;
        case AttachmentBottomSheetResult.screenshot:
          widget.onSendScreenshot();
          break;
        case AttachmentBottomSheetResult.reaction:
          widget.onOpenReactionPicker();
          break;
        case AttachmentBottomSheetResult.poll:
          widget.onSendPoll();
          break;
        case AttachmentBottomSheetResult.gif:
          widget.onSendGif();
          break;
        case AttachmentBottomSheetResult.checklist:
          widget.onSendChecklist();
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.enabled;
    final isUploading = widget.isUploading;
    final isEditing = widget.isEditing;
    final onSend = widget.onSend;
    final controller = widget.controller;
    final uploadFileName = widget.uploadFileName;
    final uploadProgress = widget.uploadProgress;
    final isRecordingVoice = widget.isRecordingVoice;
    final hasVoiceDraft = widget.hasVoiceDraft;
    final isVoiceLocked = widget.isVoiceLocked;
    final holdPhase = isRecordingVoice && !isVoiceLocked;
    final voiceSlideCancelArmed = widget.voiceSlideCancelArmed;
    final voiceGestureOffset = widget.voiceGestureOffset;
    final lockedOrDraftBar = (isRecordingVoice || hasVoiceDraft) && !holdPhase;
    final recordingDuration = widget.recordingDuration;
    final isVoiceRecordingActive = isRecordingVoice || hasVoiceDraft;

    final isVoicePaused = widget.isVoicePaused;
    final onResumeVoiceNote = widget.onResumeVoiceNote;
    final onPauseVoiceNote = widget.onPauseVoiceNote;
    final onStopVoiceNote = widget.onStopVoiceNote;
    final onCancelVoiceNote = widget.onCancelVoiceNote;
    final onSendVoiceNote = widget.onSendVoiceNote;
    final onVoiceLongPressStart = widget.onVoiceLongPressStart;
    final onVoiceLongPressMove = widget.onVoiceLongPressMove;
    final onVoiceLongPressEnd = widget.onVoiceLongPressEnd;
    final isVoiceHoldActive = widget.isVoiceHoldActive;
    final enterSendsMessage = widget.enterSendsMessage;
    final onChanged = widget.onChanged;

    final showVoiceActionButtons =
        (isVoiceRecordingActive && isVoiceLocked) || hasVoiceDraft;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
              child: _TelegramComposerUploadStrip(
                colorScheme: colorScheme,
                fileName: uploadFileName ?? 'مرفق',
                progress: uploadProgress,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // WhatsApp style Input Capsule
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surfaceContainerHigh
                        : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.outlineVariant
                          .withValues(alpha: isDark ? 0.35 : 0.22),
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.25 : 0.04,
                        ),
                        blurRadius: 6,
                        offset: const Offset(0, 1.5),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: holdPhase
                      ? _VoiceHoldRecordingBar(
                          colorScheme: colorScheme,
                          durationLabel: _formatDuration(recordingDuration),
                          slideCancelArmed: voiceSlideCancelArmed,
                          gestureOffset: voiceGestureOffset,
                          isDark: isDark,
                          onCancel: onCancelVoiceNote,
                        )
                      : lockedOrDraftBar
                          ? Row(
                              children: [
                                IconButton(
                                  tooltip: 'إلغاء وحذف',
                                  onPressed: enabled ? onCancelVoiceNote : null,
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFEF4444),
                                    size: 24,
                                  ),
                                ),
                                Expanded(
                                  child: _VoiceRecordingLockedBar(
                                    colorScheme: colorScheme,
                                    durationLabel:
                                        _formatDuration(recordingDuration),
                                    isLocked: isVoiceLocked || !isRecordingVoice,
                                    isPaused: isVoicePaused,
                                    isDark: isDark,
                                  ),
                                ),
                                if (isRecordingVoice)
                                  IconButton(
                                    tooltip: isVoicePaused
                                        ? 'استئناف'
                                        : 'إيقاف مؤقت',
                                    onPressed: enabled
                                        ? (isVoicePaused
                                            ? onResumeVoiceNote
                                            : onPauseVoiceNote)
                                        : null,
                                    icon: Icon(
                                      isVoicePaused
                                          ? Icons.mic_rounded
                                          : Icons.pause_circle_outline_rounded,
                                      size: 24,
                                      color: isVoicePaused
                                          ? const Color(0xFFEF4444)
                                          : (isDark ? Colors.white70 : const Color(0xFF64748B)),
                                    ),
                                  ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Left: Emoji button
                                IconButton(
                                  tooltip: 'التعبيرات والرموز',
                                  onPressed: enabled && !isUploading
                                      ? (widget.onOpenEmojiPicker ?? widget.onSendGif)
                                      : null,
                                  splashRadius: 20,
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 44,
                                  ),
                                  icon: Icon(
                                    Icons.sentiment_satisfied_rounded,
                                    size: 24,
                                    color: isDark
                                        ? Colors.white70
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                                // Center: Text field expanding to fill all available space
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: ChatTextFieldPasteMenu(
                                      controller: controller,
                                      enabled: enabled,
                                      child: TextField(
                                        controller: controller,
                                        enabled: enabled,
                                        minLines: 1,
                                        maxLines: 6,
                                        onChanged: onChanged,
                                        textInputAction: enterSendsMessage
                                            ? TextInputAction.send
                                            : TextInputAction.newline,
                                        onSubmitted:
                                            enterSendsMessage && enabled
                                                ? (_) => onSend()
                                                : null,
                                        style: TextStyle(
                                          fontSize: 16,
                                          height: 1.3,
                                          color: isDark
                                              ? const Color(0xFFF8FAFC)
                                              : const Color(0xFF0F172A),
                                        ),
                                        decoration: InputDecoration(
                                          hintText: enabled
                                              ? (isEditing
                                                  ? 'عدّل الرسالة...'
                                                  : 'اكتب رسالة...')
                                              : 'المحادثة للقراءة فقط',
                                          hintStyle: TextStyle(
                                            fontSize: 15.5,
                                            color: isDark
                                                ? Colors.white38
                                                : const Color(0xFF94A3B8),
                                          ),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 4,
                                                vertical: 11,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Trailing attachment and camera inside bubble
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: controller,
                                  builder: (context, value, _) {
                                    final hasText =
                                        value.text.trim().isNotEmpty ||
                                        isEditing;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // Attachment (Paperclip) button
                                        IconButton(
                                          tooltip: 'إرفاق',
                                          onPressed: enabled && !isUploading
                                              ? _openActionsMenu
                                              : null,
                                          splashRadius: 20,
                                          padding: const EdgeInsets.all(8),
                                          constraints: const BoxConstraints(
                                            minWidth: 38,
                                            minHeight: 44,
                                          ),
                                          icon: Icon(
                                            Icons.attach_file_rounded,
                                            size: 23,
                                            color: isDark
                                                ? Colors.white70
                                                : const Color(0xFF64748B),
                                          ),
                                        ),
                                        // Camera button (disappears smoothly when user starts typing)
                                        AnimatedSize(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          curve: Curves.easeInOutCubic,
                                          child: hasText
                                              ? const SizedBox.shrink()
                                              : IconButton(
                                                  tooltip: 'الكاميرا',
                                                  onPressed:
                                                      enabled && !isUploading
                                                          ? widget.onTakePhoto
                                                          : null,
                                                  splashRadius: 20,
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 38,
                                                        minHeight: 44,
                                                      ),
                                                  icon: Icon(
                                                    Icons.camera_alt_rounded,
                                                    size: 22,
                                                    color: isDark
                                                        ? Colors.white70
                                                        : const Color(
                                                            0xFF64748B,
                                                          ),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                ),
              ),
              const SizedBox(width: 6),
              // WhatsApp Circular Action Button (Mic / Send) with Floating Lock Capsule
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  if (holdPhase && isVoiceHoldActive)
                    Positioned(
                      bottom: 58,
                      child: _VoiceLockPill(
                        gestureDy: voiceGestureOffset.dy,
                        isDark: isDark,
                        colorScheme: colorScheme,
                      ),
                    ),
                  _buildCircularActionButton(
                    context: context,
                    colorScheme: colorScheme,
                    enabled: enabled,
                    isUploading: isUploading,
                    uploadProgress: uploadProgress,
                    isEditing: isEditing,
                    showVoiceActionButtons: showVoiceActionButtons,
                    onSendVoiceNote: onSendVoiceNote,
                    onSend: onSend,
                    onSendOptions: widget.onSendOptions,
                    onVoiceLongPressStart: onVoiceLongPressStart,
                    onVoiceLongPressMove: onVoiceLongPressMove,
                    onVoiceLongPressEnd: onVoiceLongPressEnd,
                    isVoiceRecordingActive: isVoiceRecordingActive,
                    isHoldingVoice: holdPhase && isVoiceHoldActive,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularActionButton({
    required BuildContext context,
    required ColorScheme colorScheme,
    required bool enabled,
    required bool isUploading,
    required double uploadProgress,
    required bool isEditing,
    required bool showVoiceActionButtons,
    required VoidCallback onSendVoiceNote,
    required VoidCallback onSend,
    required VoidCallback onSendOptions,
    required Future<void> Function() onVoiceLongPressStart,
    required void Function(LongPressMoveUpdateDetails) onVoiceLongPressMove,
    required Future<void> Function() onVoiceLongPressEnd,
    required bool isVoiceRecordingActive,
    bool isHoldingVoice = false,
  }) {
    const whatsappGreen = Color(0xFF00A884);

    if (showVoiceActionButtons) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: whatsappGreen,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: whatsappGreen.withValues(alpha: 0.38),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onSendVoiceNote : null,
            child: const Center(
              child: Icon(Icons.send_rounded, size: 22, color: Colors.white),
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty || isEditing;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: hasText
              ? Container(
                  key: const ValueKey('send_btn'),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: enabled && !isUploading ? onSend : null,
                      onLongPress: enabled && !isUploading && !isEditing
                          ? onSendOptions
                          : null,
                      child: Center(
                        child: isUploading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  value: uploadProgress <= 0
                                      ? null
                                      : uploadProgress,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                isEditing
                                    ? Icons.check_rounded
                                    : Icons.send_rounded,
                                size: 21,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                )
              : Tooltip(
                  key: const ValueKey('mic_btn'),
                  message: 'اضغط مطوّلاً للتسجيل',
                  child: IgnorePointer(
                    ignoring: !enabled || isUploading,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'اضغط مطوّلاً على المايك لتسجيل رسالة صوتية',
                              textAlign: TextAlign.center,
                            ),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      onLongPressStart: (_) =>
                          unawaited(onVoiceLongPressStart()),
                      onLongPressMoveUpdate: onVoiceLongPressMove,
                      onLongPressEnd: (_) =>
                          unawaited(onVoiceLongPressEnd()),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: isHoldingVoice ? 54 : 48,
                        height: isHoldingVoice ? 54 : 48,
                        decoration: BoxDecoration(
                          color: isHoldingVoice ? whatsappGreen : colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (isHoldingVoice ? whatsappGreen : colorScheme.primary)
                                  .withValues(alpha: isHoldingVoice ? 0.45 : 0.32),
                              blurRadius: isHoldingVoice ? 12 : 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.mic_rounded,
                            size: isHoldingVoice ? 26 : 23,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _VoiceRecordingLockedBar extends StatefulWidget {
  const _VoiceRecordingLockedBar({
    required this.colorScheme,
    required this.durationLabel,
    required this.isLocked,
    this.isPaused = false,
    required this.isDark,
  });

  final ColorScheme colorScheme;
  final String durationLabel;
  final bool isLocked;
  final bool isPaused;
  final bool isDark;

  @override
  State<_VoiceRecordingLockedBar> createState() => _VoiceRecordingLockedBarState();
}

class _VoiceRecordingLockedBarState extends State<_VoiceRecordingLockedBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (!widget.isPaused) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _VoiceRecordingLockedBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused && _pulseController.isAnimating) {
      _pulseController.stop();
    } else if (!widget.isPaused && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Pulsing red dot (or static gray dot when paused)
        if (!widget.isPaused)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final opacity = 0.35 + (_pulseController.value * 0.65);
              return Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: opacity),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: opacity * 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              );
            },
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF94A3B8),
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 8),
        Text(
          widget.durationLabel,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RecordingWaveform(isPaused: widget.isPaused),
        ),
      ],
    );
  }
}

class _RecordingWaveform extends StatefulWidget {
  const _RecordingWaveform({this.isPaused = false});

  final bool isPaused;

  @override
  State<_RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<_RecordingWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (!widget.isPaused) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPaused && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.isPaused && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const waveColor = Color(0xFF00A884);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(14, (i) {
              final phase = (t * 6.28318) + (i * 0.55);
              final v = widget.isPaused
                  ? 0.3
                  : (0.35 + 0.65 * (math.sin(phase))).clamp(0.15, 1.0);
              final h = 5 + (v * 18);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 2.8,
                  height: h,
                  decoration: BoxDecoration(
                    color: waveColor.withValues(alpha: widget.isPaused ? 0.35 : 0.8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

// (Removed) Slide-to-lock/cancel voice recording UI.

String _presenceLabel(ChatDirectoryUser user) {
  if (user.presenceStatus == 'online') return 'متصل الآن';

  if (user.presenceStatus == 'idle') {
    final at = user.lastActiveAt ?? user.lastSeen;
    return at == null ? 'خامل' : 'خامل منذ ${formatEgyptTime(at)}';
  }

  final lastSeen = user.lastSeen ?? user.lastActiveAt;
  return lastSeen == null
      ? 'غير متصل'
      : 'آخر ظهور ${formatEgyptDateTime(lastSeen)}';
}

Color _presenceColor(String status) => switch (status) {
  'online' => const Color(0xFF22C55E),
  'idle' => const Color(0xFFF59E0B),
  _ => const Color(0xFF94A3B8),
};

_MessageStatus _status(ChatMessage message, String currentUserId) {
  if (message.isFailed) {
    return const _MessageStatus(Icons.error_outline_rounded, Color(0xFFEF4444));
  }
  if (message.isPending || message.id.startsWith('temp_')) {
    return const _MessageStatus(Icons.access_time_rounded, Color(0xFF94A3B8));
  }

  if (message.seenBy.any((entry) => entry.userId != currentUserId)) {
    return const _MessageStatus(Icons.done_all_rounded, Color(0xFF16A34A));
  }

  if (message.deliveredTo.any((entry) => entry.userId != currentUserId)) {
    return const _MessageStatus(Icons.done_all_rounded, Color(0xFF94A3B8));
  }

  return const _MessageStatus(Icons.done_rounded, Color(0xFF94A3B8));
}

IconData _attachmentIcon(String type) => switch (type) {
  'image' => Icons.image_outlined,
  'pdf' => Icons.picture_as_pdf_outlined,
  'audio' => Icons.mic_rounded,
  _ => Icons.attach_file,
};

List<MapEntry<String, List<String>>> _reactionEntries(ChatMessage message) {
  final metadata = message.metadata;
  if (metadata == null) {
    return const [];
  }

  final rawReactions = metadata['reactions'];
  if (rawReactions is! Map) {
    return const [];
  }

  return rawReactions.entries
      .where((entry) => entry.key != null && entry.value is List)
      .map(
        (entry) => MapEntry(
          entry.key.toString(),
          (entry.value as List<dynamic>)
              .map((userId) => userId.toString())
              .toList(),
        ),
      )
      .where((entry) => entry.value.isNotEmpty)
      .toList();
}

/// ترتيب مثل تيليجرام: الأكثر تفاعلًا أولًا ثم حسب الإيموجي.
List<MapEntry<String, List<String>>> _sortedReactionEntries(
  ChatMessage message,
) {
  final entries = List<MapEntry<String, List<String>>>.from(
    _reactionEntries(message),
  );
  entries.sort((a, b) {
    final byCount = b.value.length.compareTo(a.value.length);
    if (byCount != 0) {
      return byCount;
    }
    return a.key.compareTo(b.key);
  });
  return entries;
}

bool _reactionHasUser(List<String> userIds, String? currentUserId) {
  if (currentUserId == null || currentUserId.isEmpty) {
    return false;
  }
  return userIds.contains(currentUserId);
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
          _pageController.previousPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (_currentIndex < widget.images.length - 1) {
          _pageController.nextPage(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
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
                    child: _ChatAttachmentImage(
                      message: widget.images[index],
                      fit: BoxFit.contain,
                      height: 400,
                      width: double.infinity,
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
                  onPressed: () =>
                      widget.onDownload(widget.images[_currentIndex], context),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
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
