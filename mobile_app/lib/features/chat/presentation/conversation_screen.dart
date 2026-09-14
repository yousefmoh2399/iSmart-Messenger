import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gal/gal.dart';
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
import 'group_management_screen.dart';
import 'widgets/attachment_bottom_sheet.dart';
import 'widgets/chat_animated_reaction_picker.dart';
import 'widgets/chat_audio_attachment_player.dart';
import 'widgets/chat_avatar.dart';
import 'widgets/chat_link_text.dart';
import 'widgets/chat_poll_bubble.dart';
import 'widgets/chat_text_field_paste_menu.dart';
import 'widgets/gif_picker_panel.dart';
import 'widgets/poll_creator_dialog.dart';
import 'widgets/scheduled_messages_list.dart';

/// خطوط احتياطية لعرض الإيموجي ملوّنًا (مهم على سطح المكتب/لينكس).
const List<String> _kChatReactionEmojiFontFallbacks = <String>[
  'Noto Color Emoji',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Segoe UI Symbol',
];

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.conversation});

  final ChatConversation conversation;

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
  ChatMessage? _editingMessage;

  late final ProviderContainer _container;

  int _lastMessageCount = 0;
  bool _isLoadingMore = false;
  bool _didAutoScrollOnEnter = false;
  bool _showScrollToLatestButton = false;
  DateTime? _lastLoadMoreAt;
  bool _didSendTyping = false;
  String? _focusedMessageId;
  bool _isUploadingAttachment = false;
  double _uploadProgress = 0;
  String? _uploadingFileName;
  bool _isDownloadingAttachment = false;
  double _downloadProgress = 0;
  String? _downloadingFileName;
  bool _broadcastSendToAllDepartments = true;
  Set<String> _broadcastTargetDepartmentIds = <String>{};
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _container.read(activeConversationIdProvider.notifier).state =
          widget.conversation.id;
      _container.read(chatSocketServiceProvider).markActivity();
      ref
          .read(
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
          )
          .markSeen();
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

      if (event.payload['conversationId'] != widget.conversation.id) {
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

    final shouldShowScrollToLatest = !_isNearBottom();
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

    if (_scrollController.position.pixels <= 120) {
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
    final previousMaxExtent = _scrollController.position.maxScrollExtent;

    try {
      await ref
          .read(
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
          )
          .loadMore();

      if (!mounted || !_scrollController.hasClients) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;

        final newMaxExtent = _scrollController.position.maxScrollExtent;
        final delta = newMaxExtent - previousMaxExtent;
        if (delta <= 0) {
          return;
        }
        final targetOffset = _scrollController.offset + delta;

        _scrollController.jumpTo(
          targetOffset.clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          ),
        );
      });
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
    final role = ref.read(authControllerProvider).valueOrNull?.role;
    return role == 'admin' ? _chatMaxUploadBytesAdmin : _chatMaxUploadBytesUser;
  }

  void _showChatAttachmentSizeExceededSnackbar() {
    if (!mounted) {
      return;
    }
    final isAdmin =
        ref.read(authControllerProvider).valueOrNull?.role == 'admin';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isAdmin
              ? 'الحد الأقصى لحجم مرفقات الشات للمسؤول هو 200 ميجا.'
              : 'الحد الأقصى لحجم مرفقات الشات هو 20 ميجا فقط.',
        ),
      ),
    );
  }

  @override
  void dispose() {
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
    );
  }

  void _showSendOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_off_rounded),
                title: const Text('إرسال بدون صوت'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendText(isSilent: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('جدولة الرسالة'),
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
                      // check if it's in the future
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

    if (_editingMessage != null) {
      await notifier.editMessage(messageId: _editingMessage!.id, content: text);
    } else {
      await notifier.sendText(
        text,
        replyToMessageId: _replyingTo?.id,
        metadata: payloadMetadata.isEmpty ? null : payloadMetadata,
        isSilent: isSilent,
        scheduledFor: scheduledFor,
      );
    }

    _messageController.clear();
    unawaited(_draftStore.clear(widget.conversation.id));

    setState(() {
      _replyingTo = null;
      _editingMessage = null;
      if (authUserId != null && authUserId.isNotEmpty) {
        _typingUsers.remove(authUserId);
      }
    });

    notifier.stopTyping();
    _didSendTyping = false;

    _scrollToBottom(animated: true);
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

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
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

  Future<void> _createPoll() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) return;

    final pollData = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          const PollCreatorDialog(), // Will fix the import using prefix or direct
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

  Future<void> _openGifPicker() async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) return;

    // For now we'll just show a simple snackbar or implement tenor API if requested.
    // Given the prompt "GIFs: دمج أداة بحث سريعة لإرسال الـ GIFs (عبر Giphy)", we should build a simple GifPicker.
    // Let's call a widget:
    final gifUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const GifPickerPanel(),
    );

    if (gifUrl != null && mounted) {
      await ref
          .read(
            conversationMessagesControllerProvider(
              widget.conversation.id,
            ).notifier,
          )
          .sendMessage(
            content: '',
            messageType: 'gif',
            fileUrl: gifUrl,
            replyToMessageId: _replyingTo?.id,
          );
      setState(() => _replyingTo = null);
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
                        title: const Text('منع إعادة التوجيه والتحميل'),
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
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final o = details.offsetFromOrigin;
    final cancel = rtl ? o.dx > 76 : o.dx < -76;
    final lock = o.dy < -72;
    setState(() {
      _voiceGestureOffset = o;
      _voiceSlideCancelArmed = cancel;
      if (lock && !_isVoiceRecordingLocked) {
        _isVoiceRecordingLocked = true;
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
              'تم تنزيل ${message.fileName ?? 'المرفق'} بنجاح\nمسار الحفظ: $savedFolder',
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
          _isDownloadingAttachment = false;
          _downloadProgress = 0;
          _downloadingFileName = null;
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

    if (message.isImageMessage) {
      await Gal.putImage(localPath, album: 'Workplace Chat');
      return 'معرض الصور (Workplace Chat)';
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

  Future<void> _openAttachment(ChatMessage message) {
    if (message.isImageMessage) {
      return _showImagePreview(message);
    }
    if (!message.attachmentDownloadAllowed) {
      if (!mounted) {
        return Future<void>.value();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذا الملف للعرض فقط داخل الشات.')),
      );
      return Future<void>.value();
    }
    return _downloadAttachment(message, openAfterDownload: true);
  }

  void _scrollToBottom({bool animated = false}) {
    unawaited(_settleScrollToBottom(animated: animated));
  }

  Future<void> _settleScrollToBottom({required bool animated}) async {
    for (var i = 0; i < 2; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
    }

    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final correctedTarget = _scrollController.position.maxScrollExtent;
    if ((_scrollController.offset - correctedTarget).abs() > 1) {
      _scrollController.jumpTo(correctedTarget);
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return (_scrollController.position.maxScrollExtent -
            _scrollController.position.pixels) <=
        120;
  }

  List<ChatMessage> _deduplicateMessagesById(List<ChatMessage> input) {
    if (input.length < 2) {
      return input;
    }
    final seen = <String>{};
    final dedupedReversed = <ChatMessage>[];
    for (final message in input.reversed) {
      if (seen.add(message.id)) {
        dedupedReversed.add(message);
      }
    }
    return dedupedReversed.reversed.toList();
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
    final key = _messageKeys[messageId];
    final targetContext = key?.currentContext;
    if (targetContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.2,
    );
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
    if (departments.isEmpty) {
      return {
        'broadcastTargets': {
          'departmentIds': const <String>[],
          'departmentCodes': const <String>[],
          'departmentNames': const <String>[],
        },
      };
    }

    final selectedIds = <String>{..._broadcastTargetDepartmentIds};
    var sendToAll = _broadcastSendToAllDepartments || selectedIds.isEmpty;

    final selection = await showModalBottomSheet<bool>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,

      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'إرسال البث إلى',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: sendToAll,
                    onChanged: (value) {
                      setModalState(() {
                        sendToAll = value;
                      });
                    },
                    title: const Text('كل الأقسام'),
                    subtitle: const Text(
                      'لو أغلقتها، اختار أقسام محددة للبث الحالي فقط.',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      children: departments
                          .map(
                            (department) => CheckboxListTile(
                              value: sendToAll
                                  ? true
                                  : selectedIds.contains(department.id),
                              onChanged: sendToAll
                                  ? null
                                  : (value) {
                                      setModalState(() {
                                        if (value == true) {
                                          selectedIds.add(department.id);
                                        } else {
                                          selectedIds.remove(department.id);
                                        }
                                      });
                                    },
                              title: Text(department.name),
                              subtitle: Text(
                                department.description.isEmpty
                                    ? 'قسم ${department.code}'
                                    : department.description,
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: (!sendToAll && selectedIds.isEmpty)
                              ? null
                              : () => Navigator.of(sheetContext).pop(true),
                          child: const Text('إرسال'),
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

    if (selection != true) {
      return null;
    }

    _broadcastSendToAllDepartments = sendToAll;
    _broadcastTargetDepartmentIds = sendToAll ? <String>{} : selectedIds;
    final selectedDepartments = sendToAll
        ? const <DepartmentSummary>[]
        : departments.where((entry) => selectedIds.contains(entry.id)).toList();
    final selectedDepartmentIds = selectedDepartments
        .map((entry) => entry.id.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    final selectedDepartmentCodes = selectedDepartments
        .map((entry) => entry.code.trim().toUpperCase())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    final selectedDepartmentNames = selectedDepartments
        .map((entry) => entry.name.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);

    return {
      'broadcastTargets': {
        'departmentIds': sendToAll ? const <String>[] : selectedDepartmentIds,
        'departmentCodes': sendToAll
            ? const <String>[]
            : selectedDepartmentCodes,
        'departmentNames': sendToAll
            ? const <String>[]
            : selectedDepartmentNames,
      },
    };
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

    final conversations = overview.conversations
        .where((conversation) => conversation.id != widget.conversation.id)
        .toList();
    ChatConversation? target;

    await showModalBottomSheet<void>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,

      builder: (sheetContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.82,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'إعادة توجيه ${selectedMessages.length} رسالة',
                        style: Theme.of(sheetContext).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: conversations.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد محادثات أخرى متاحة لإعادة التوجيه.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: conversations.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final conversation = conversations[index];
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            tileColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLowest,
                            title: Text(
                              conversation.displayTitle(
                                ref
                                        .read(authControllerProvider)
                                        .valueOrNull
                                        ?.id ??
                                    '',
                              ),
                            ),
                            subtitle: Text(switch (conversation.type) {
                              'direct' => 'محادثة مباشرة',
                              'department' => 'غرفة قسم',
                              'broadcast' => 'قناة إعلانية',
                              _ => 'مجموعة',
                            }),
                            onTap: () {
                              target = conversation;
                              Navigator.of(sheetContext).pop();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );

    if (target == null) {
      return;
    }

    final repository = ref.read(chatRepositoryProvider);

    var skippedRestrictedCount = 0;
    try {
      for (final message in selectedMessages) {
        if (message.hasAttachment && !message.attachmentForwardAllowed) {
          skippedRestrictedCount++;
          continue;
        }
        final metadata = _forwardMetadataFor(message);
        await repository.forwardMessage(
          conversationId: target!.id,
          sourceMessageId: message.id,
          metadata: metadata,
        );
      }

      unawaited(ref.read(chatOverviewControllerProvider.notifier).refresh());
      if (!mounted) {
        return;
      }
      _clearSelection();
      final forwardedCount = selectedMessages.length - skippedRestrictedCount;
      final targetName = target!.displayTitle(
        ref.read(authControllerProvider).valueOrNull?.id ?? '',
      );
      if (forwardedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت إعادة توجيه $forwardedCount رسالة إلى $targetName',
            ),
          ),
        );
      }
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

  Future<void> _showActions(ChatMessage message) async {
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id;
    if (_isReadOnlyFor(authUserId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_readOnlyTextFor(authUserId))));
      return;
    }

    final authUser = ref.read(authControllerProvider).valueOrNull;
    // final canDelete =
    //     authUser?.id == message.senderId ||
    //     authUser?.can('canDeleteMessages') == true;
    final senderId = message.sender?.id ?? message.senderId;

    final isMine = authUser?.id.toString() == senderId.toString();

    final canDelete = isMine || authUser?.can('canDeleteMessages') == true;

    final canEdit = isMine && !message.hasAttachment && !message.isDeleted;
    final previewText = message.content.isNotEmpty
        ? message.content
        : (message.fileName ?? 'مرفق');

    final quickReactionRow = await buildQuickReactionUnicodeRow();
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,

      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.84,
          ),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.sender?.displayName ??
                            (isMine ? 'أنت' : 'مستخدم'),
                        style: const TextStyle(
                          color: Color(0xFF3390EC),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        previewText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: quickReactionRow
                      .map(
                        (emoji) => ChatAnimatedReactionQuickChip(
                          emoji: emoji,
                          size: 30,
                          onTap: () async {
                            Navigator.pop(context);
                            await ref
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
                        ),
                      )
                      .toList(),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _showFullReactionPicker(message);
                    },
                    icon: const Icon(Icons.add_reaction_outlined),
                    label: const Text('المزيد من التفاعلات'),
                  ),
                ),
                const SizedBox(height: 8),
                _TelegramActionTile(
                  icon: Icons.reply_rounded,
                  label: 'رد',
                  color: const Color(0xFF3390EC),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _replyingTo = message;
                      _editingMessage = null;
                    });
                  },
                ),
                if (!message.hasAttachment || message.attachmentForwardAllowed)
                  _TelegramActionTile(
                    icon: Icons.forward_to_inbox_rounded,
                    label: 'إعادة توجيه',
                    color: const Color(0xFF19A974),
                    onTap: () async {
                      Navigator.pop(context);
                      setState(() {
                        _selectedMessageIds
                          ..clear()
                          ..add(message.id);
                      });
                      await _forwardSelectedMessages(
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
                if (message.isPrintableAttachment)
                  _TelegramActionTile(
                    icon: Icons.print_rounded,
                    label: 'طباعة عبر الكمبيوتر',
                    color: const Color(0xFF0EA5A4),
                    onTap: () async {
                      Navigator.pop(context);
                      await _requestAttachmentPrint(message);
                    },
                  ),
                if (message.hasAttachment && message.attachmentDownloadAllowed)
                  _TelegramActionTile(
                    icon: Icons.download_rounded,
                    label: 'تنزيل من جديد',
                    color: const Color(0xFF19A974),
                    onTap: () async {
                      Navigator.pop(context);
                      await _downloadAttachment(message);
                    },
                  ),
                _TelegramActionTile(
                  icon: message.isFavoritedBy(authUser?.id)
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: message.isFavoritedBy(authUser?.id)
                      ? 'إزالة من المفضلة'
                      : 'إضافة إلى المفضلة',
                  color: const Color(0xFFF59E0B),
                  onTap: () async {
                    Navigator.pop(context);
                    await ref
                        .read(
                          conversationMessagesControllerProvider(
                            widget.conversation.id,
                          ).notifier,
                        )
                        .toggleFavoriteMessage(messageId: message.id);
                  },
                ),
                if (widget.conversation.type != 'direct' && isMine)
                  _TelegramActionTile(
                    icon: Icons.info_outline_rounded,
                    label: 'تفاصيل الرسالة',
                    color: const Color(0xFF3390EC),
                    onTap: () {
                      Navigator.pop(context);
                      _showMessageDetails(message);
                    },
                  ),
                if (canEdit)
                  _TelegramActionTile(
                    icon: Icons.edit_outlined,
                    label: 'تعديل',
                    color: const Color(0xFFF59E0B),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _editingMessage = message;
                        _replyingTo = null;
                        _messageController.text = message.content;
                      });
                    },
                  ),
                if (_canManagePinnedMessage(authUserId))
                  _TelegramActionTile(
                    icon: Icons.push_pin_outlined,
                    label: 'ØªØ«Ø¨ÙŠØª',
                    color: const Color(0xFF9A6400),
                    onTap: () async {
                      Navigator.pop(context);
                      await ref
                          .read(chatOverviewControllerProvider.notifier)
                          .setGroupPinnedMessage(
                            conversationId: widget.conversation.id,
                            content: previewText,
                            messageId: message.id,
                          );
                    },
                  ),
                if (canDelete && !message.isDeleted)
                  _TelegramActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'حذف',
                    color: const Color(0xFFE53935),
                    onTap: () async {
                      Navigator.pop(context);
                      await ref
                          .read(
                            conversationMessagesControllerProvider(
                              widget.conversation.id,
                            ).notifier,
                          )
                          .deleteMessage(message.id);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showFullReactionPicker(ChatMessage message) async {
    final sections = buildPickerSections(
      chatPickerAnimatedEmojis(),
      const <String, int>{},
    );
    await showModalBottomSheet<void>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,

      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.32,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          final titleSmall = theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          );
          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 4, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'اختر تفاعلًا',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                if (sections.frequentTop.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Text('الأكثر استخدامًا', style: titleSmall),
                  ),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      scrollDirection: Axis.horizontal,
                      itemCount: sections.frequentTop.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 2),
                      itemBuilder: (context, i) {
                        final data = sections.frequentTop[i];
                        return SizedBox(
                          width: 60,
                          child: ChatAnimatedReactionOption(
                            data: data,
                            size: 44,
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await ref
                                  .read(
                                    conversationMessagesControllerProvider(
                                      widget.conversation.id,
                                    ).notifier,
                                  )
                                  .toggleReaction(
                                    messageId: message.id,
                                    emoji: data.toUnicodeEmoji(),
                                  );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                    child: Text('باقي التفاعلات', style: titleSmall),
                  ),
                ],
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      8,
                      sections.frequentTop.isEmpty ? 4 : 0,
                      8,
                      12,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                          childAspectRatio: 1,
                        ),
                    itemCount: sections.gridRest.length,
                    itemBuilder: (context, index) {
                      final data = sections.gridRest[index];
                      return ChatAnimatedReactionOption(
                        data: data,
                        size: 38,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await ref
                              .read(
                                conversationMessagesControllerProvider(
                                  widget.conversation.id,
                                ).notifier,
                              )
                              .toggleReaction(
                                messageId: message.id,
                                emoji: data.toUnicodeEmoji(),
                              );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
      title: 'مسح المحادثة عندي',
      description: 'سيتم مسح الرسائل عندك فقط مع بقاء المحادثة ظاهرة.',
      confirmLabel: 'مسح',
    );
    if (!shouldClear || !mounted) {
      return;
    }

    try {
      await ref
          .read(chatOverviewControllerProvider.notifier)
          .deleteConversation(widget.conversation.id);
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
        const SnackBar(content: Text('تم مسح المحادثة عندك بنجاح')),
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
        ).showSnackBar(const SnackBar(content: Text('تم مسح المحادثة بالفعل')));
        return;
      }
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'من شاهد الرسالة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Expanded(
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
                    final seenBy =
                        snapshot.data?['seenBy'] as List<dynamic>? ?? [];
                    if (seenBy.isEmpty) {
                      return const Center(child: Text('لم يشاهدها أحد بعد.'));
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: seenBy.length,
                      itemBuilder: (context, index) {
                        final user = seenBy[index] as Map<String, dynamic>;
                        return ListTile(
                          leading: ChatAvatar(
                            avatarUrl: user['avatarUrl']?.toString() ?? '',
                            radius: 20,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            fallback: Text(
                              user['displayName']?.toString().isNotEmpty == true
                                  ? user['displayName']
                                        .toString()[0]
                                        .toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(
                            user['displayName']?.toString() ?? 'مستخدم',
                          ),
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
            ],
          ),
        ),
      ),
    );
  }

  void _showScheduledMessagesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              AppBar(
                title: const Text('الرسائل المجدولة'),
                leading: const CloseButton(),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              Expanded(
                child: ScheduledMessagesList(
                  conversationId: widget.conversation.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSearchSheet() async {
    final notifier = ref.read(
      conversationMessagesControllerProvider(widget.conversation.id).notifier,
    );

    final controller = TextEditingController();
    List<ChatMessage> results = const <ChatMessage>[];
    bool isLoading = false;
    String? errorText;

    Future<void> runSearch(StateSetter setSheetState) async {
      final query = controller.text.trim();
      if (query.isEmpty) {
        setSheetState(() {
          results = const <ChatMessage>[];
          errorText = null;
        });
        return;
      }

      setSheetState(() {
        isLoading = true;
        errorText = null;
      });

      try {
        final result = await notifier.searchMessages(query);
        setSheetState(() {
          results = result.messages;
        });
      } catch (error) {
        setSheetState(() {
          errorText = error.toString();
        });
      } finally {
        setSheetState(() => isLoading = false);
      }
    }

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => runSearch(setSheetState),
                    decoration: InputDecoration(
                      hintText: 'ابحث في كل رسائل المحادثة',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => runSearch(setSheetState),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: isLoading
                        ? const Center(child: AppLoadingIndicator(size: 28))
                        : errorText != null
                        ? Center(child: Text(errorText!))
                        : results.isEmpty
                        ? Center(
                            child: Text(
                              controller.text.trim().isEmpty
                                  ? 'اكتب كلمة أو جملة للبحث داخل كل الرسائل.'
                                  : 'لا توجد نتائج مطابقة.',
                            ),
                          )
                        : ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final message = results[index];
                              final title =
                                  message.sender?.displayName.isNotEmpty == true
                                  ? message.sender!.displayName
                                  : 'رسالة';
                              final preview = message.content.isNotEmpty
                                  ? message.content
                                  : (message.fileName ?? 'مرفق');

                              return InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () async {
                                  Navigator.of(context).pop();
                                  await _jumpToSearchMessage(
                                    message,
                                    query: controller.text,
                                  );
                                },
                                child: Ink(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.42),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                          ),
                                          Text(
                                            formatEgyptDateTime(
                                              message.createdAt,
                                              datePattern: 'dd/MM',
                                              separator: ' • ',
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        preview,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
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
          ),
        ),
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

  Future<void> _showImagePreview(ChatMessage message) async {
    if (!mounted || message.fileUrl == null || message.fileUrl!.isEmpty) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Hero(
                  tag: 'image_${message.id}',
                  child: _ChatAttachmentImage(
                    message: message,
                    fit: BoxFit.contain,
                    height: 400,
                    width: double.infinity,
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
    final canDeleteForEveryone =
        authUser?.role == 'admin' || _data.createdBy == authUser?.id;
    final canManagePinnedMessage = _canManagePinnedMessage(authUser?.id);
    final typingIndicatorText = _typingUsers.isEmpty
        ? null
        : (_data.type == 'direct'
              ? 'يكتب الآن...'
              : '${_typingUsers.values.join('، ')} يكتب الآن...');

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
              : Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      child: peer?.avatarUrl?.isNotEmpty == true
                          ? ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: peer!.avatarUrl!,
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
                          ),
                          Text(
                            effectiveStatusText,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
              IconButton(
                onPressed: () => _showScheduledMessagesSheet(),
                icon: const Icon(Icons.schedule_rounded),
                tooltip: 'الرسائل المجدولة',
              ),
              IconButton(
                onPressed: () => _showSearchSheet(),
                icon: const Icon(Icons.search_rounded),
                tooltip: 'بحث',
              ),
              IconButton(
                onPressed: () => _showSharedMediaSheet(loadedMessages, token),
                icon: const Icon(Icons.perm_media_outlined),
                tooltip: 'الوسائط',
              ),
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
                    value: 'clear',
                    child: Text('مسح المحادثة عندي'),
                  ),
                  if (_data.type != 'direct')
                    const PopupMenuItem(
                      value: 'leave',
                      child: Text('مغادرة المجموعة'),
                    ),
                  if (canDeleteForEveryone)
                    const PopupMenuItem(
                      value: 'delete_everyone',
                      child: Text('حذف نهائي للجميع'),
                    ),
                ],
              ),
            ],
          ],
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
                    loading: () => const _ChatMessagesLoadingSkeleton(),
                    error: (error, _) => Center(child: Text(error.toString())),
                    data: (messagesData) {
                      final messages = _deduplicateMessagesById(
                        messagesData.messages,
                      );
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
                        _didAutoScrollOnEnter = false;
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
                      }

                      final hasNewMessages =
                          messages.length > _lastMessageCount;
                      if (!_didAutoScrollOnEnter) {
                        _didAutoScrollOnEnter = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted || !_scrollController.hasClients) {
                            return;
                          }
                          _scrollController.jumpTo(
                            _scrollController.position.maxScrollExtent,
                          );
                          _scrollToBottom();
                        });
                      }
                      final shouldAutoScroll =
                          _lastMessageCount == 0 ||
                          (_isNearBottom() && !_isLoadingMore);

                      if (hasNewMessages && shouldAutoScroll) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _scrollToBottom();
                        });
                      }

                      _lastMessageCount = messages.length;

                      final hasTopBanner =
                          isReadOnly ||
                          (_data.pinnedMessage != null &&
                              _data.pinnedMessage!.content.trim().isNotEmpty);

                      return ListView.builder(
                        controller: _scrollController,
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
                            messages.length +
                            (messagesData.isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Center(
                                child: AppLoadingIndicator(size: 28),
                              ),
                            );
                          }

                          final message = messages[index];
                          final previous = index > 0
                              ? messages[index - 1]
                              : null;

                          final messageLocalDate = message.createdAt.toLocal();
                          final previousLocalDate = previous?.createdAt
                              .toLocal();

                          final showDate =
                              previousLocalDate == null ||
                              previousLocalDate.day != messageLocalDate.day ||
                              previousLocalDate.month !=
                                  messageLocalDate.month ||
                              previousLocalDate.year != messageLocalDate.year;

                          final senderId =
                              message.sender?.id ?? message.senderId;

                          final isMine =
                              authUser?.id.toString() == senderId.toString();

                          final next = index < messages.length - 1
                              ? messages[index + 1]
                              : null;
                          final isLastInGroup =
                              next == null ||
                              next.sender?.id != message.sender?.id ||
                              next.createdAt
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

                          Widget child = RepaintBoundary(
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
                                        DateFormat(
                                          'yyyy/MM/dd',
                                        ).format(messageLocalDate),
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
                                      onTap: _selectionMode
                                          ? () => _toggleMessageSelection(
                                              message.id,
                                            )
                                          : () => _showActions(message),
                                      onLongPress: () =>
                                          _toggleMessageSelection(message.id),
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
                                              key: _messageKeys.putIfAbsent(
                                                message.id,
                                                GlobalKey.new,
                                              ),
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
                                                          bottom: 10,
                                                          left: isMine ? 34 : 0,
                                                          right: isMine
                                                              ? 0
                                                              : 34,
                                                        ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 14,
                                                              vertical: 10,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: isSelected
                                                              ? const Color(
                                                                  0xFF3390EC,
                                                                ).withValues(
                                                                  alpha: 0.14,
                                                                )
                                                              : (isFocused
                                                                    ? const Color(
                                                                        0xFFFDF3C7,
                                                                      )
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
                                                                  22,
                                                                ),
                                                            topRight:
                                                                const Radius.circular(
                                                                  22,
                                                                ),
                                                            bottomLeft:
                                                                Radius.circular(
                                                                  isMine
                                                                      ? 22
                                                                      : 6,
                                                                ),
                                                            bottomRight:
                                                                Radius.circular(
                                                                  isMine
                                                                      ? 6
                                                                      : 22,
                                                                ),
                                                          ),
                                                          border: Border.all(
                                                            color: isSelected
                                                                ? const Color(
                                                                    0xFF3390EC,
                                                                  )
                                                                : (isFocused
                                                                      ? const Color(
                                                                          0xFFF59E0B,
                                                                        )
                                                                      : bubbleBorderColor),
                                                            width:
                                                                isSelected ||
                                                                    isFocused
                                                                ? 1.4
                                                                : 1,
                                                          ),
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
                                                              if (_data.type ==
                                                                      'broadcast' &&
                                                                  (message.sentToAllDepartments ||
                                                                      message
                                                                          .broadcastTargetDepartmentNames
                                                                          .isNotEmpty))
                                                                Container(
                                                                  width: double
                                                                      .infinity,
                                                                  margin:
                                                                      const EdgeInsets.only(
                                                                        bottom:
                                                                            8,
                                                                      ),
                                                                  padding:
                                                                      const EdgeInsets.symmetric(
                                                                        horizontal:
                                                                            10,
                                                                        vertical:
                                                                            7,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    color:
                                                                        const Color(
                                                                          0xFFE67E22,
                                                                        ).withValues(
                                                                          alpha:
                                                                              0.1,
                                                                        ),
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          12,
                                                                        ),
                                                                  ),
                                                                  child: Text(
                                                                    message.sentToAllDepartments
                                                                        ? 'إرسال إلى كل الأقسام'
                                                                        : 'إرسال إلى: ${message.broadcastTargetDepartmentNames.join('، ')}',
                                                                    maxLines: 2,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style: const TextStyle(
                                                                      color: Color(
                                                                        0xFFB85714,
                                                                      ),
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                ),
                                                              if (replyPreview !=
                                                                  null)
                                                                Container(
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
                                                                          'deleted_${message.id}',
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
                                                                          'content_${message.id}',
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
                                                                              padding: const EdgeInsets.only(
                                                                                top: 10,
                                                                              ),
                                                                              child: message.isAudioMessage
                                                                                  ? ChatAudioAttachmentPlayer(
                                                                                      message: message,
                                                                                    )
                                                                                  : message.isImageMessage
                                                                                  ? InkWell(
                                                                                      onTap: () => _openAttachment(
                                                                                        message,
                                                                                      ),
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
                                                                                            tag: 'image_${message.id}',
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
                                                                                  : InkWell(
                                                                                      onTap: () => _openAttachment(
                                                                                        message,
                                                                                      ),
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        14,
                                                                                      ),
                                                                                      child: Container(
                                                                                        width: double.infinity,
                                                                                        padding: const EdgeInsets.all(
                                                                                          10,
                                                                                        ),
                                                                                        decoration: BoxDecoration(
                                                                                          color: replyBgColor,
                                                                                          borderRadius: BorderRadius.circular(
                                                                                            14,
                                                                                          ),
                                                                                        ),
                                                                                        child: Row(
                                                                                          children: [
                                                                                            Icon(
                                                                                              _attachmentIcon(
                                                                                                message.messageType,
                                                                                              ),
                                                                                              color: textColor,
                                                                                            ),
                                                                                            const SizedBox(
                                                                                              width: 8,
                                                                                            ),
                                                                                            Flexible(
                                                                                              child: Text(
                                                                                                message.fileName ??
                                                                                                    'ملف مرفق',
                                                                                                maxLines: 1,
                                                                                                overflow: TextOverflow.ellipsis,
                                                                                                style: TextStyle(
                                                                                                  color: textColor,
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                            if (message.isPrintableAttachment)
                                                                                              IconButton(
                                                                                                visualDensity: VisualDensity.compact,
                                                                                                onPressed: () => _requestAttachmentPrint(
                                                                                                  message,
                                                                                                ),
                                                                                                icon: Icon(
                                                                                                  Icons.print_rounded,
                                                                                                  size: 18,
                                                                                                  color: subTextColor,
                                                                                                ),
                                                                                              ),
                                                                                            Icon(
                                                                                              message.attachmentDownloadAllowed
                                                                                                  ? Icons.download_rounded
                                                                                                  : Icons.lock_rounded,
                                                                                              size: 18,
                                                                                              color: subTextColor,
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                            ),
                                                                        ],
                                                                      ),
                                                              ),
                                                              const SizedBox(
                                                                height: 8,
                                                              ),
                                                              Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Text(
                                                                    formatEgyptTime(
                                                                      messageLocalDate,
                                                                    ),
                                                                    style: TextStyle(
                                                                      color:
                                                                          subTextColor,
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                  if (message
                                                                      .isEdited) ...[
                                                                    const SizedBox(
                                                                      width: 6,
                                                                    ),
                                                                    Text(
                                                                      'معدلة',
                                                                      style: TextStyle(
                                                                        color:
                                                                            subTextColor,
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                  if (status !=
                                                                      null) ...[
                                                                    const SizedBox(
                                                                      width: 6,
                                                                    ),
                                                                    Icon(
                                                                      status
                                                                          .icon,
                                                                      size: 16,
                                                                      color: status
                                                                          .color,
                                                                    ),
                                                                  ],
                                                                ],
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

                          if (!_animatedMessageIds.contains(message.id)) {
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
                if (_isDownloadingAttachment)
                  _DownloadBanner(
                    colorScheme: colorScheme,
                    fileName: _downloadingFileName ?? 'مرفق',
                    progress: _downloadProgress,
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
                    onSendSpecificFile: _sendSpecificFile,
                    onSendScreenshot: _sendScreenshotFromDevice,
                    onOpenReactionPicker: _showComposerReactionPicker,
                    onSendPoll: _createPoll,
                    onSendChecklist: _createChecklist,
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

class _TelegramActionTile extends StatelessWidget {
  const _TelegramActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
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

class _DownloadBanner extends StatelessWidget {
  const _DownloadBanner({
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

class _VoiceHoldRecordingBar extends StatelessWidget {
  const _VoiceHoldRecordingBar({
    required this.colorScheme,
    required this.durationLabel,
    required this.slideCancelArmed,
    required this.gestureOffset,
  });

  final ColorScheme colorScheme;
  final String durationLabel;
  final bool slideCancelArmed;
  final Offset gestureOffset;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dx = rtl ? -gestureOffset.dx * 0.22 : gestureOffset.dx * 0.22;
    final cancelColor = slideCancelArmed
        ? const Color(0xFFDC2626)
        : colorScheme.onSurfaceVariant;
    return Transform.translate(
      offset: Offset(dx, gestureOffset.dy * 0.08),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: slideCancelArmed
                ? const Color(0xFFFCA5A5)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
              size: 20,
              color: cancelColor,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                slideCancelArmed ? 'اترك للإلغاء' : 'اسحب للإلغاء',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: cancelColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              durationLabel,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            const SizedBox(width: 72, child: _RecordingWaveform()),
          ],
        ),
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
    this.onSendSpecificFile,
    required this.onSendScreenshot,
    required this.onOpenReactionPicker,
    required this.onSendPoll,
    required this.onSendChecklist,
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
  final ValueChanged<String>? onSendSpecificFile;
  final VoidCallback onSendScreenshot;
  final VoidCallback onOpenReactionPicker;
  final VoidCallback onSendPoll;
  final VoidCallback onSendChecklist;
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
  double _sendScale = 1.0;

  void _scaleSendButton(bool scaleDown) {
    if (!mounted) return;
    setState(() => _sendScale = scaleDown ? 0.9 : 1.0);
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final enabled = widget.enabled;
    final isUploading = widget.isUploading;
    final isEditing = widget.isEditing;
    final onAttach = widget.onAttach;
    final onPickImage = widget.onPickImage;
    final onSendScreenshot = widget.onSendScreenshot;
    final onOpenReactionPicker = widget.onOpenReactionPicker;
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

    /// أزرار التحكم تظهر دائمًا أثناء التسجيل أو مع مسودة (لا نعتمد على وضع القفل فقط).
    final showVoiceActionButtons = isVoiceRecordingActive;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUploading)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
                child: _TelegramComposerUploadStrip(
                  colorScheme: colorScheme,
                  fileName: uploadFileName ?? 'مرفق',
                  progress: uploadProgress,
                ),
              ),
            Row(
              children: [
                if (!isVoiceRecordingActive) ...[
                  _ComposerActionsFab(
                    enabled: enabled && !isUploading,
                    colorScheme: colorScheme,
                    onAttach: onAttach,
                    onPickImage: onPickImage,
                    onSendSpecificFile: widget.onSendSpecificFile,
                    onSendScreenshot: onSendScreenshot,
                    onOpenReactionPicker: onOpenReactionPicker,
                    onSendPoll: widget.onSendPoll,
                    onSendChecklist: widget.onSendChecklist,
                    onSendGif: widget.onSendGif,
                  ),
                ],
                Expanded(
                  child: holdPhase
                      ? _VoiceHoldRecordingBar(
                          colorScheme: colorScheme,
                          durationLabel: _formatDuration(recordingDuration),
                          slideCancelArmed: voiceSlideCancelArmed,
                          gestureOffset: voiceGestureOffset,
                        )
                      : lockedOrDraftBar
                      ? _VoiceRecordingLockedBar(
                          colorScheme: colorScheme,
                          durationLabel: _formatDuration(recordingDuration),
                          isLocked: isVoiceLocked || !isRecordingVoice,
                        )
                      : ChatTextFieldPasteMenu(
                          controller: controller,
                          enabled: enabled,
                          child: TextField(
                            controller: controller,
                            enabled: enabled,
                            minLines: 1,
                            maxLines: 5,
                            onChanged: onChanged,
                            textInputAction: enterSendsMessage
                                ? TextInputAction.send
                                : TextInputAction.newline,
                            onSubmitted: enterSendsMessage && enabled
                                ? (_) => onSend()
                                : null,
                            decoration: InputDecoration(
                              hintText: enabled
                                  ? (isEditing
                                        ? 'عدّل الرسالة...'
                                        : 'اكتب رسالة...')
                                  : 'الغرفة للقراءة فقط',
                              border: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 4),
                if (showVoiceActionButtons) ...[
                  if (isRecordingVoice) ...[
                    IconButton.filledTonal(
                      onPressed: enabled
                          ? (isVoicePaused
                                ? onResumeVoiceNote
                                : onPauseVoiceNote)
                          : null,
                      tooltip: isVoicePaused ? 'استئناف' : 'إيقاف مؤقت',
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                      icon: Icon(
                        isVoicePaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      onPressed: enabled ? onStopVoiceNote : null,
                      tooltip: 'إيقاف وحفظ مسودة',
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                      icon: const Icon(Icons.stop_rounded),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton.filledTonal(
                    onPressed: enabled ? onCancelVoiceNote : null,
                    tooltip: 'إلغاء التسجيل',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFFE4E6),
                    ),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: hasVoiceDraft ? 'إرسال' : 'إرسال الملاحظة الصوتية',
                    child: FilledButton(
                      onPressed: enabled ? onSendVoiceNote : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ] else
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty || isEditing;
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: hasText
                            ? Stack(
                                key: const ValueKey('send_btn'),
                                alignment: Alignment.center,
                                children: [
                                  if (isUploading)
                                    SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.6,
                                        value: uploadProgress <= 0
                                            ? null
                                            : uploadProgress,
                                        color: const Color(0xFF3390EC),
                                        backgroundColor:
                                            colorScheme.surfaceContainerHighest,
                                      ),
                                    ),
                                  GestureDetector(
                                    onTapDown: (_) => _scaleSendButton(true),
                                    onTapUp: (_) => _scaleSendButton(false),
                                    onTapCancel: () => _scaleSendButton(false),
                                    onLongPress:
                                        enabled && !isUploading && !isEditing
                                        ? widget.onSendOptions
                                        : null,
                                    child: AnimatedScale(
                                      scale: _sendScale,
                                      duration: const Duration(
                                        milliseconds: 100,
                                      ),
                                      child: FilledButton(
                                        onPressed: enabled && !isUploading
                                            ? onSend
                                            : null,
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          padding: EdgeInsets.zero,
                                          shape: const CircleBorder(),
                                        ),
                                        child: Icon(
                                          isEditing
                                              ? Icons.check_rounded
                                              : Icons.send_rounded,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Tooltip(
                                key: const ValueKey('mic_btn'),
                                message: 'اضغط مطوّلاً للتسجيل',
                                child: IgnorePointer(
                                  ignoring:
                                      !enabled ||
                                      isUploading ||
                                      isVoiceRecordingActive,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onLongPressStart: (_) =>
                                        unawaited(onVoiceLongPressStart()),
                                    onLongPressMoveUpdate: onVoiceLongPressMove,
                                    onLongPressEnd: (_) =>
                                        unawaited(onVoiceLongPressEnd()),
                                    child: Container(
                                      width: 48,
                                      height: 48,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color:
                                            colorScheme.surfaceContainerHighest,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.mic_rounded,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      );
                    },
                  ),
              ],
            ),
            if (holdPhase && isVoiceHoldActive)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Text(
                  'اسحب للأعلى للقفل ثم التعديل قبل الإرسال',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VoiceRecordingLockedBar extends StatelessWidget {
  const _VoiceRecordingLockedBar({
    required this.colorScheme,
    required this.durationLabel,
    required this.isLocked,
  });

  final ColorScheme colorScheme;
  final String durationLabel;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    final fg = colorScheme.onSurfaceVariant;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            isLocked ? Icons.lock_rounded : Icons.mic_rounded,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Text(
            durationLabel,
            style: TextStyle(fontWeight: FontWeight.w800, color: fg),
          ),
          const SizedBox(width: 10),
          const Expanded(child: _RecordingWaveform()),
        ],
      ),
    );
  }
}

class _RecordingWaveform extends StatefulWidget {
  const _RecordingWaveform();

  @override
  State<_RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<_RecordingWaveform>
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
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(10, (i) {
              final phase = (t * 6.28318) + (i * 0.6);
              final v = (0.5 + 0.5 * (math.sin(phase))).clamp(0.0, 1.0);
              final h = 6 + (v * 14);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: 3,
                  height: h,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.65),
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

class _ComposerActionsFab extends StatefulWidget {
  const _ComposerActionsFab({
    required this.enabled,
    required this.colorScheme,
    required this.onAttach,
    required this.onPickImage,
    this.onSendSpecificFile,
    required this.onSendScreenshot,
    required this.onOpenReactionPicker,
    this.onSendPoll,
    this.onSendChecklist,
    this.onSendGif,
  });

  final bool enabled;
  final ColorScheme colorScheme;
  final VoidCallback onAttach;
  final VoidCallback onPickImage;
  final ValueChanged<String>? onSendSpecificFile;
  final VoidCallback onSendScreenshot;
  final VoidCallback onOpenReactionPicker;
  final VoidCallback? onSendPoll;
  final VoidCallback? onSendChecklist;
  final VoidCallback? onSendGif;

  @override
  State<_ComposerActionsFab> createState() => _ComposerActionsFabState();
}

class _ComposerActionsFabState extends State<_ComposerActionsFab> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _openActionsMenu() async {
    if (!widget.enabled) {
      return;
    }

    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null) {
      return;
    }

    final selected = await showModalBottomSheet<dynamic>(
      context: anchorContext,
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
          widget.onSendPoll?.call();
          break;
        case AttachmentBottomSheetResult.gif:
          widget.onSendGif?.call();
          break;
        case AttachmentBottomSheetResult.checklist:
          widget.onSendChecklist?.call();
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: IconButton.filledTonal(
        key: _anchorKey,
        onPressed: widget.enabled ? _openActionsMenu : null,
        style: IconButton.styleFrom(
          backgroundColor: widget.colorScheme.surfaceContainerHighest,
        ),
        icon: const Icon(Icons.add_rounded),
      ),
    );
  }
}

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
