import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/chat/presentation/chat_home_screen.dart';
import '../features/chat/presentation/conversation_screen.dart';
import '../features/chat/models/chat_models.dart';
import '../features/chat/presentation/widgets/chat_avatar.dart';
import '../features/tickets/presentation/tickets_screen.dart';
import '../shared/models/update_models.dart';
import '../shared/providers/providers.dart';
import '../shared/services/mobile_update_agent.dart';
import '../shared/services/android_share_receiver.dart';
import '../shared/widgets/loading_view.dart';
import '../shared/widgets/update_dialog.dart';

class WorkplaceMobileApp extends ConsumerWidget {
  const WorkplaceMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(appBootstrapProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final chatPreferences = ref.watch(currentChatPreferencesProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ماسح المستندات',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme(chatPreferences),
      darkTheme: AppTheme.darkTheme(chatPreferences),
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 300),
      themeAnimationCurve: Curves.easeInOutCubic,
      home: bootstrap.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(message: 'جارٍ تجهيز التطبيق...'),
        error: (error, stackTrace) =>
            LoadingView(message: error.toString(), isError: true),
        data: (status) {
          if (status == BootstrapStatus.failed) {
            return const LoadingView(
              message: 'فشل تهيئة التطبيق.',
              isError: true,
            );
          }
          return const _AuthGate();
        },
      ),
    );
  }
}

class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

enum _IncomingFileSaveTarget { quickSaveDefault, chooseLocation, cancel }

class _AuthGateState extends ConsumerState<_AuthGate>
    with WidgetsBindingObserver {
  String? _lastPresenceUserId;
  ProviderSubscription<AuthState>? _authSubscription;
  late final MobileUpdateAgent _updateAgent;
  bool _isUpdateDialogOpen = false;
  StreamSubscription? _socketEventsSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Map<String, dynamic>>? _notificationTapSubscription;
  StreamSubscription<Map<String, dynamic>>? _pushOpenedSubscription;
  bool _isAutoSyncingPending = false;
  bool _isHandlingNotificationNavigation = false;
  Map<String, dynamic>? _pendingNotificationPayload;
  String? _lastServerBannerMessage;
  bool _serverRefreshInFlight = false;
  bool _hasConfirmedServerDisconnect = false;
  int _serverFailureStreak = 0;
  bool _serverRestoreRefreshInFlight = false;
  StreamSubscription<AndroidSharedContent>? _androidShareSubscription;
  AndroidSharedContent? _pendingAndroidShare;
  bool _shareSheetOpen = false;
  String? _directShareTargetsSignature;

  // Event-driven connection flag.
  // True while the app is still establishing/re-establishing its connection to
  // the server. Suppresses false-positive "server unavailable" banners during
  // cold start and background-to-foreground transitions.
  // Cleared as soon as the socket confirms connection or a health-check succeeds.
  // A 30-second fallback timer surfaces genuine outages if neither event fires.
  bool _isEstablishingConnection = true;
  Timer? _connectionEstablishTimer;
  static const _connectionEstablishTimeoutDuration = Duration(seconds: 30);

  void _setChatVisibility(bool isVisible) {
    final current = ref.read(chatAppVisibilityProvider);
    if (current == isVisible) {
      return;
    }
    Future.microtask(() {
      if (mounted) {
        ref.read(chatAppVisibilityProvider.notifier).state = isVisible;
      }
    });
  }

  void _handleAuthStatusChange(AuthState auth) {
    if (!mounted) {
      return;
    }
    if (auth.status == AuthStatus.unauthenticated) {
      debugPrint('[_AuthGateState] User logged out');
      _lastPresenceUserId = null;
      _lastServerBannerMessage = null;
      _setChatVisibility(false);
      ref.read(chatSocketServiceProvider).setPresenceOffline();
      ref.read(chatSocketServiceProvider).disconnect();
      unawaited(_updateAgent.clearUpdateState());
      _updateAgent.stop();
      _isEstablishingConnection = true;
      _connectionEstablishTimer?.cancel();
      return;
    }

    if (auth.status == AuthStatus.authenticated) {
      final user = auth.user!;
      if (_lastPresenceUserId == user.id) {
        ref
            .read(pushNotificationServiceProvider)
            .registerForAuthenticatedUser();
        unawaited(_tryHandleNotificationNavigation());
        return;
      }

      debugPrint('[_AuthGateState] User changed: ${user.username}');
      _lastPresenceUserId = user.id;
      // Reset server-disconnect state for the new session so stale banners
      // from the previous user's logout don't surface.
      _hasConfirmedServerDisconnect = false;
      _lastServerBannerMessage = null;
      _markConnectionEstablishing();
      final isVisible =
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      _setChatVisibility(isVisible);

      final socket = ref.read(chatSocketServiceProvider);
      if (isVisible) {
        socket.setPresenceOnline();
      } else {
        socket.setPresenceIdle();
      }

      ref.read(pushNotificationServiceProvider).registerForAuthenticatedUser();

      debugPrint(
        '[_AuthGateState] Preparing update agent for ${user.username}',
      );
      unawaited(_updateAgent.start(user));
      ref.invalidate(remoteDocumentsControllerProvider);
      ref.invalidate(adminDocumentsControllerProvider);
      unawaited(_syncAdminServerDefaults());
      // Use quiet=true on login so a transient connectivity hiccup doesn't
      // immediately show the server-unavailable banner to the newly logged-in user.
      unawaited(_refreshServerConnectionState(quiet: true));
      unawaited(_syncPendingUploadsInBackground());
      unawaited(_tryHandleNotificationNavigation());
    }
  }

  Future<void> _syncAdminServerDefaults() async {
    try {
      final defaults = await ref
          .read(appSettingsServiceProvider)
          .fetchDefaults();
      final mobileUrl = defaults.mobileBaseUrl?.trim();
      if (mobileUrl == null || mobileUrl.isEmpty) {
        return;
      }
      await ref
          .read(apiBaseUrlControllerProvider.notifier)
          .applyAdminDefault(mobileUrl);
      await ref.read(serverConnectionControllerProvider.notifier).refresh();
    } catch (_) {}
  }

  /// Marks the app as actively connecting/re-connecting.
  /// Suppresses error banners until the connection is established.
  /// A fallback timer fires after 30 s to surface genuine outages.
  void _markConnectionEstablishing() {
    if (!mounted) return;
    _isEstablishingConnection = true;
    _connectionEstablishTimer?.cancel();
    _connectionEstablishTimer = Timer(_connectionEstablishTimeoutDuration, () {
      if (!mounted) return;
      _isEstablishingConnection = false;
      unawaited(_refreshServerConnectionState());
    });
  }

  /// Marks the app as successfully connected.
  /// Cancels the fallback timer and allows error banners to surface.
  void _markConnectionEstablished() {
    if (!mounted) return;
    _isEstablishingConnection = false;
    _connectionEstablishTimer?.cancel();
  }

  Future<void> _refreshServerConnectionState({
    bool quiet = false,
    bool refreshAfterRestore = true,
  }) async {
    if (_serverRefreshInFlight) {
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) {
      return;
    }
    _serverRefreshInFlight = true;
    late final ServerConnectionState result;
    try {
      result = await ref
          .read(serverConnectionControllerProvider.notifier)
          .refresh(preserveConnectedStateOnFailure: quiet);
    } finally {
      _serverRefreshInFlight = false;
    }
    if (!mounted) {
      return;
    }
    if (!result.isConnected) {
      if (quiet ||
          _isEstablishingConnection ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      _serverFailureStreak++;
      if (_serverFailureStreak >= 2) {
        _hasConfirmedServerDisconnect = true;
      }
      return;
    }
    // Connection confirmed — clear establishing flag immediately.
    _markConnectionEstablished();
    _serverFailureStreak = 0;
    if (_hasConfirmedServerDisconnect || _lastServerBannerMessage != null) {
      _hasConfirmedServerDisconnect = false;
      _lastServerBannerMessage = null;
      if (refreshAfterRestore) {
        unawaited(_refreshDataAfterServerRestored());
      }
    }
    _hasConfirmedServerDisconnect = false;
    _lastServerBannerMessage = null;
  }

  Future<void> _ensureSocketConnected() async {
    final socket = ref.read(chatSocketServiceProvider);
    if (socket.isConnected) return;
    try {
      final token = await ref.read(authTokenProvider.future);
      if (token == null || token.isEmpty) return;
      final baseUrl = ref.read(apiBaseUrlControllerProvider).valueOrNull ??
          AppConfig.defaultApiBaseUrl;
      await socket.connect(
        baseUrl: baseUrl,
        token: token,
        clientType: 'mobile',
      );
    } catch (_) {}
  }

  Future<void> _refreshDataAfterServerRestored() async {
    if (_serverRestoreRefreshInFlight) {
      return;
    }
    _serverRestoreRefreshInFlight = true;
    try {
      try {
        await _ensureSocketConnected();
      } catch (_) {}
      if (!mounted) {
        return;
      }
      try {
        ref.read(chatOverviewControllerProvider.notifier).refresh(showLoader: false);
      } catch (_) {}
      final activeConversationId = ref.read(activeConversationIdProvider);
      if (activeConversationId != null && activeConversationId.isNotEmpty) {
        try {
          ref
              .read(
                conversationMessagesControllerProvider(
                  activeConversationId,
                ).notifier,
              )
              .refresh();
        } catch (_) {}
      }
      ref.read(pushNotificationServiceProvider).registerForAuthenticatedUser();
      unawaited(_syncPendingUploadsInBackground());
    } finally {
      _serverRestoreRefreshInFlight = false;
    }
  }

  void _showConnectionSnackBar(String message, {required bool isError}) {
    // Suppress intrusive disconnect SnackBars during normal mobile usage (WhatsApp style)
    return;
  }

  String _buildServerUnavailableMessage(String details) {
    final trimmed = details.trim();
    if (trimmed.isEmpty) {
      return 'الخادم غير متاح الآن. تحقق من اتصال الإنترنت أو من حالة السيرفر ثم أعد المحاولة.';
    }
    return 'تعذر الوصول إلى الخادم. $trimmed';
  }

  Future<void> _retryServerConnection() async {
    try {
      await ref.read(serverConnectionControllerProvider.notifier).refresh();
      ref.read(serverRecoveryRevisionProvider.notifier).state++;
      ref.invalidate(chatSocketConnectionProvider);
      try {
        await ref.read(authControllerProvider.notifier).refreshCurrentUser();
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _changeServerBaseUrl() async {
    final currentBaseUrl =
        ref.read(apiBaseUrlControllerProvider).valueOrNull ??
        AppConfig.defaultApiBaseUrl;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ChangeServerBaseUrlDialog(
        initialUrl: currentBaseUrl,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    if (result == '__reset__') {
      await ref.read(apiBaseUrlControllerProvider.notifier).reset();
    } else if (result.trim().isNotEmpty) {
      await ref.read(apiBaseUrlControllerProvider.notifier).save(result.trim());
    } else {
      return;
    }

    ref.invalidate(authControllerProvider);
    ref.invalidate(remoteDocumentsControllerProvider);
    ref.invalidate(adminDocumentsControllerProvider);
    ref.invalidate(ticketsControllerProvider);
    ref.invalidate(mobilePrinterControllerProvider);
    await _retryServerConnection();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Start in connecting state — suppresses false-positive banners on cold start.
    // Will be cleared when the socket connects or a health check succeeds.
    _markConnectionEstablishing();

    // Initialize update agent
    _updateAgent = MobileUpdateAgent(ref.read(updateCheckServiceProvider));
    _initializeUpdateAgent();

    _authSubscription = ref.listenManual<AuthState>(
      authControllerProvider,
      (_, next) => _handleAuthStatusChange(next),
      fireImmediately: true,
    );
    _listenToNotificationNavigation();
    _listenToSocketFileRequests();
    _listenToConnectivityChanges();
    _listenToAndroidShares();
  }

  Future<void> _listenToAndroidShares() async {
    _androidShareSubscription = AndroidShareReceiver.events.listen(
      _presentIncomingShare,
    );
    final initial = await AndroidShareReceiver.initialize();
    if (initial != null) _presentIncomingShare(initial);
  }

  Future<void> _presentIncomingShare(AndroidSharedContent content) async {
    _pendingAndroidShare = content;
    if (_shareSheetOpen) return;
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _pendingAndroidShare != null) {
          _presentIncomingShare(_pendingAndroidShare!);
        }
      });
      return;
    }
    final conversations =
        ref.read(chatOverviewControllerProvider).valueOrNull?.conversations ??
        const [];
    if (conversations.isEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _pendingAndroidShare != null) {
          _presentIncomingShare(_pendingAndroidShare!);
        }
      });
      return;
    }
    _shareSheetOpen = true;
    _pendingAndroidShare = null;
    final directConversation = content.conversationId == null
        ? null
        : conversations
              .where((entry) => entry.id == content.conversationId)
              .firstOrNull;
    if (directConversation != null) {
      await _sendSharedContentToConversation(content, directConversation);
      _shareSheetOpen = false;
      if (mounted) {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) =>
                ConversationScreen(conversation: directConversation),
          ),
        );
      }
      return;
    }

    final currentUserId = ref.read(currentUserProvider)?.id ?? '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ShareBottomSheet(
        content: content,
        conversations: conversations,
        currentUserId: currentUserId,
        onSelected: (conversation) async {
          Navigator.pop(sheetContext);
          await _sendSharedContentToConversation(content, conversation);
          if (mounted) {
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) =>
                    ConversationScreen(conversation: conversation),
              ),
            );
          }
        },
      ),
    );
    _shareSheetOpen = false;
  }

  // ── Share-sheet helpers ────────────────────────────────────────────────────

  static String _getConversationTitle(
    ChatConversation conversation,
    String currentUserId,
  ) => conversation.displayTitle(currentUserId);

  static String? _getConversationAvatarUrl(
    ChatConversation conversation,
    String currentUserId,
  ) {
    if (conversation.type == 'direct') {
      final other = conversation.members
          .where((m) => m.id != currentUserId)
          .firstOrNull;
      return other?.avatarUrl;
    }
    return null;
  }

  static String _avatarLetter(
    ChatConversation conversation,
    String currentUserId,
  ) {
    final title = conversation.displayTitle(currentUserId);
    return title.trim().isEmpty
        ? '?'
        : title.trim().characters.first.toUpperCase();
  }

  static String _getConversationSubtitle(
    ChatConversation conversation, [
    String? currentUserId,
  ]) {
    if (currentUserId != null && conversation.isSelfChat(currentUserId)) {
      return 'الملاحظات والملفات المحفوظة';
    }
    final last = conversation.lastMessage;
    if (last == null) return 'لا توجد رسائل';
    final type = last.messageType;
    if (type == 'image') return '🖼️ صورة';
    if (type == 'file') return '📎 مرفق';
    final text = last.content.trim();
    return text.isEmpty ? '...' : text;
  }

  Future<void> _sendSharedContentToConversation(
    AndroidSharedContent content,
    ChatConversation conversation,
  ) async {
    final controller = ref.read(
      conversationMessagesControllerProvider(conversation.id).notifier,
    );
    final mediaGroupId = content.paths.length > 1
        ? 'album_${DateTime.now().microsecondsSinceEpoch}'
        : null;
    if (content.text.trim().isNotEmpty) {
      await controller.sendMessage(content: content.text.trim());
    }
    for (final path in content.paths) {
      await controller.sendFile(
        path,
        metadata: mediaGroupId == null
            ? null
            : {
                'mediaGroupId': mediaGroupId,
                'mediaGroupSize': content.paths.length,
              },
      );
    }
  }

  void _publishDirectShareTargets(List<ChatConversation> conversations) {
    final targets = conversations
        .where((c) => c.isActive)
        .take(8)
        .map(
          (c) => {
            'id': c.id,
            'label': c.name.trim().isEmpty ? 'محادثة' : c.name.trim(),
          },
        )
        .toList();
    final signature = targets.map((e) => '${e['id']}:${e['label']}').join('|');
    if (signature == _directShareTargetsSignature) return;
    _directShareTargetsSignature = signature;
    AndroidShareReceiver.updateDirectShareTargets(targets).catchError((_) {});
  }

  void _listenToNotificationNavigation() {
    _notificationTapSubscription?.cancel();
    _pushOpenedSubscription?.cancel();

    final localNotifications = ref.read(localNotificationServiceProvider);
    final pushNotifications = ref.read(pushNotificationServiceProvider);

    // Initialize local notifications early to catch cold-start launch details
    unawaited(localNotifications.initialize().then((_) {
      if (!mounted) return;
      final pendingLocalPayload = localNotifications.takePendingLaunchPayload();
      if (pendingLocalPayload != null) {
        _queueNotificationNavigation(pendingLocalPayload);
      }
    }));

    _notificationTapSubscription = localNotifications.tapEvents.listen(
      _queueNotificationNavigation,
    );
    _pushOpenedSubscription = pushNotifications.openedNotifications.listen(
      _queueNotificationNavigation,
    );

    final pendingOpenedPayload = pushNotifications.takePendingOpenedPayload();
    if (pendingOpenedPayload != null) {
      _queueNotificationNavigation(pendingOpenedPayload);
    }
  }

  void _queueNotificationNavigation(Map<String, dynamic> payload) {
    if (payload.isEmpty) {
      return;
    }
    _pendingNotificationPayload = payload;
    unawaited(_tryHandleNotificationNavigation());
  }

  Future<void> _tryHandleNotificationNavigation() async {
    if (!mounted || _isHandlingNotificationNavigation) {
      return;
    }
    final user = ref.read(currentUserProvider);
    final payload = _pendingNotificationPayload;
    if (user == null || payload == null || payload.isEmpty) {
      return;
    }

    final type = payload['type']?.toString().trim() ?? '';
    final conversationId = payload['conversationId']?.toString().trim() ?? '';
    final ticketId = payload['ticketId']?.toString().trim() ?? '';
    final isChatNotification =
        type == 'chat' || type == 'chat_reaction' || conversationId.isNotEmpty;

    if (!isChatNotification && type != 'ticket') {
      return;
    }

    // Direct inline reply from notification
    final replyText = payload['replyText']?.toString().trim();
    if (replyText != null && replyText.isNotEmpty && conversationId.isNotEmpty) {
      _pendingNotificationPayload = null;
      unawaited(_handleDirectNotificationReply(
        conversationId,
        replyText,
        payload['notificationId'],
      ));
      return;
    }

    _pendingNotificationPayload = null;
    _isHandlingNotificationNavigation = true;
    try {
      if (type == 'ticket' && ticketId.isNotEmpty && conversationId.isEmpty) {
        if (!mounted) {
          return;
        }
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => TicketDetailsScreen(ticketId: ticketId),
          ),
        );
        return;
      }

      if (conversationId.isEmpty) {
        return;
      }

      // If user is already looking at this conversation, just refresh messages
      final currentActiveId = ref.read(activeConversationIdProvider);
      if (currentActiveId == conversationId) {
        try {
          ref
              .read(
                conversationMessagesControllerProvider(
                  conversationId,
                ).notifier,
              )
              .refresh();
        } catch (_) {}
        return;
      }

      // 1. Instant open: check if conversation is already in memory overview
      ChatConversation? conversation;
      final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
      if (overview != null) {
        for (final item in overview.conversations) {
          if (item.id == conversationId) {
            conversation = item;
            break;
          }
        }
      }

      // 2. If not found in memory overview, fetch via repository
      conversation ??= await ref
          .read(chatRepositoryProvider)
          .fetchConversation(conversationId);

      if (!mounted) {
        return;
      }

      ref.read(activeConversationIdProvider.notifier).state = conversation.id;
      await Navigator.of(context, rootNavigator: true).push(
        CupertinoPageRoute(
          builder: (_) => ConversationScreen(conversation: conversation!),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح المحادثة: ${error.toString()}')),
      );
    } finally {
      _isHandlingNotificationNavigation = false;
    }
  }

  Future<void> _handleDirectNotificationReply(
    String conversationId,
    String replyText,
    dynamic notificationId,
  ) async {
    if (conversationId.isEmpty || replyText.trim().isEmpty) return;
    try {
      await ref
          .read(
            conversationMessagesControllerProvider(
              conversationId,
            ).notifier,
          )
          .sendMessage(content: replyText.trim());

      if (notificationId != null) {
        final id = int.tryParse(notificationId.toString());
        if (id != null) {
          ref.read(localNotificationServiceProvider).cancel(id);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال الرد: ${replyText.trim()}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationReply] Error sending direct reply: $e');
    }
  }

  void _listenToSocketFileRequests() {
    _socketEventsSubscription?.cancel();
    _socketEventsSubscription = ref.read(chatSocketServiceProvider).events.listen((
      event,
    ) {
      if (event.type == 'file_receive_requested') {
        unawaited(_handleIncomingFileRequest(event.payload));
        return;
      }
      if (event.type == 'attachment_rehydrate_requested') {
        unawaited(
          ref
              .read(chatRepositoryProvider)
              .respondToAttachmentRehydrate(event.payload),
        );
        return;
      }
      if (event.type == 'socket_connected') {
        // Socket connected — server reachable, clear establishing flag immediately.
        _markConnectionEstablished();
        unawaited(
          _refreshServerConnectionState(quiet: true, refreshAfterRestore: true),
        );
        unawaited(_drainChatOutbox());
        return;
      }
      if (event.type == 'announcements_updated') {
        unawaited(
          _refreshServerConnectionState(quiet: true, refreshAfterRestore: true),
        );
        return;
      }
      if (event.type == 'updates_updated') {
        unawaited(_updateAgent.checkNow(forceEmitExistingTask: true));
        return;
      }
      if (event.type == 'socket_error' || event.type == 'socket_disconnected') {
        // Ignore while still establishing or when app is in background/screen locked.
        if (_isEstablishingConnection ||
            WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
          return;
        }
        unawaited(_refreshServerConnectionState(quiet: true));
      }
    });
  }

  Future<void> _syncPendingUploadsInBackground() async {
    if (_isAutoSyncingPending) {
      return;
    }
    _isAutoSyncingPending = true;
    ref.read(syncBannerStateProvider.notifier).state = const SyncBannerState(
      isOffline: false,
      isSyncing: true,
      message: 'عاد الاتصال: جاري مزامنة الملفات المعلقة...',
    );
    try {
      final uploaded = await ref
          .read(pendingUploadsControllerProvider.notifier)
          .syncAllPendingUploads(maxItems: 12);
      if (uploaded > 0) {
        ref.read(syncBannerStateProvider.notifier).state = SyncBannerState(
          isOffline: false,
          isSyncing: false,
          message: 'تمت مزامنة $uploaded ملف/ملفات بنجاح.',
        );
      }
    } catch (_) {
      // Silent background sync.
    } finally {
      _isAutoSyncingPending = false;
      if (ref.read(syncBannerStateProvider).isSyncing) {
        ref.read(syncBannerStateProvider.notifier).state =
            SyncBannerState.hidden();
      }
    }
  }

  void _listenToConnectivityChanges() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final hasConnection = results.any(
        (entry) => entry != ConnectivityResult.none,
      );
      if (hasConnection) {
        unawaited(_refreshServerConnectionState(quiet: true));
        unawaited(_syncPendingUploadsInBackground());
        unawaited(_drainChatOutbox());
        try {
          ref.read(chatOverviewControllerProvider.notifier).refresh(showLoader: false);
        } catch (_) {}
      }
    });
  }

  Future<void> _drainChatOutbox() async {
    try {
      final outbox = ref.read(chatOutboxServiceProvider);
      final repo = ref.read(chatRepositoryProvider);
      await outbox.drainQueue(
        repository: repo,
        onConfirmed: (item, confirmed) {
          if (!mounted) return;
          try {
            ref
                .read(chatOverviewControllerProvider.notifier)
                .applyConfirmedOutboxMessage(
                  item.conversationId,
                  item.tempMessageId,
                  confirmed,
                );
          } catch (_) {}
          try {
            final activeId = ref.read(activeConversationIdProvider);
            if (activeId == item.conversationId) {
              ref
                  .read(conversationMessagesControllerProvider(item.conversationId).notifier)
                  .applyConfirmedOutboxMessage(item.tempMessageId, confirmed);
            }
          } catch (_) {}
        },
        onFailed: (item, error) {
          if (!mounted) return;
          try {
            final activeId = ref.read(activeConversationIdProvider);
            if (activeId == item.conversationId) {
              ref
                  .read(conversationMessagesControllerProvider(item.conversationId).notifier)
                  .applyFailedOutboxMessage(item.tempMessageId, error.toString());
            }
          } catch (_) {}
        },
      );
    } catch (_) {}
  }

  Future<void> _handleIncomingFileRequest(Map<String, dynamic> payload) async {
    final jobId = payload['jobId']?.toString();
    if (jobId == null || jobId.isEmpty) {
      return;
    }
    String resultMessage = 'تعذر حفظ الملف الوارد على الموبايل.';
    String? savedPath;
    var success = false;
    try {
      final fileName = payload['fileName']?.toString().trim().isNotEmpty == true
          ? payload['fileName'].toString().trim()
          : 'file';
      final declaredFileSize =
          int.tryParse(payload['fileSize']?.toString() ?? '') ?? 0;
      final transferId = payload['transferId']?.toString().trim() ?? '';
      final inlineBase64 = payload['inlineFileBase64']?.toString().trim() ?? '';
      final rawDownloadUrl = payload['downloadUrl']?.toString().trim() ?? '';
      final effectiveDownloadUrl = rawDownloadUrl.isNotEmpty
          ? rawDownloadUrl
          : (transferId.isNotEmpty
                ? '/api/chat/transfers/$transferId/download'
                : '');

      final fallbackDirectory = await _resolveIncomingFallbackDirectory();
      final saveTarget = await _showIncomingFileSaveDialog(
        fileName: fileName,
        fileSizeBytes: declaredFileSize,
        defaultDirectoryPath: fallbackDirectory.path,
      );
      if (saveTarget == null || saveTarget == _IncomingFileSaveTarget.cancel) {
        await _emitIncomingFileProgress(
          jobId,
          stage: 'rejected',
          progress: 1,
          message: 'تم رفض استقبال الملف على الموبايل.',
        );
        throw Exception('تم إلغاء حفظ الملف.');
      }

      await _emitIncomingFileProgress(
        jobId,
        stage: 'accepted',
        progress: 0.06,
        message: 'تم قبول استقبال الملف على الموبايل.',
      );

      final useSystemSaveDialog =
          Platform.isAndroid &&
          saveTarget == _IncomingFileSaveTarget.chooseLocation;
      String targetDirectory;
      if (saveTarget == _IncomingFileSaveTarget.chooseLocation &&
          !useSystemSaveDialog) {
        final selectedDirectory = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'اختر مكان حفظ الملف الوارد',
        );
        if (selectedDirectory == null || selectedDirectory.trim().isEmpty) {
          throw Exception('لم يتم اختيار مكان للحفظ.');
        }
        targetDirectory = selectedDirectory.trim();
      } else {
        targetDirectory = fallbackDirectory.path;
      }
      final targetPath = useSystemSaveDialog
          ? null
          : _resolveUniquePath(targetDirectory, fileName);
      if (inlineBase64.isNotEmpty) {
        await _emitIncomingFileProgress(
          jobId,
          stage: 'receiving',
          progress: 0.42,
          message: 'جاري تجهيز الملف الوارد على الموبايل...',
        );
        final bytes = base64Decode(inlineBase64);
        await _emitIncomingFileProgress(
          jobId,
          stage: 'saving',
          progress: 0.86,
          message: 'جاري حفظ الملف على الموبايل...',
        );
        if (useSystemSaveDialog) {
          savedPath = await _saveBytesViaSystemPicker(
            bytes: Uint8List.fromList(bytes),
            fileName: fileName,
          );
        } else {
          await File(targetPath!).writeAsBytes(bytes, flush: true);
          savedPath = targetPath;
        }
      } else if (effectiveDownloadUrl.isNotEmpty) {
        final apiClient = ref.read(authenticatedApiClientProvider);
        final resolvedDownloadUrl = _resolveTransferDownloadUrl(
          apiClient.dio.options.baseUrl,
          effectiveDownloadUrl,
        );
        if (useSystemSaveDialog) {
          final response = await apiClient.dio.get<List<int>>(
            resolvedDownloadUrl,
            options: Options(responseType: ResponseType.bytes),
            onReceiveProgress: (received, total) {
              final ratio = total <= 0
                  ? 0.0
                  : (received / total).clamp(0, 1).toDouble();
              final overallProgress = 0.12 + (ratio * 0.72);
              unawaited(
                _emitIncomingFileProgress(
                  jobId,
                  stage: 'downloading',
                  progress: overallProgress,
                  message: total > 0
                      ? 'جاري تنزيل الملف على الموبايل ${(ratio * 100).toStringAsFixed(0)}%'
                      : 'جاري تنزيل الملف على الموبايل...',
                ),
              );
            },
          );
          await _emitIncomingFileProgress(
            jobId,
            stage: 'saving',
            progress: 0.92,
            message: 'تم تنزيل الملف، اختر مكان الحفظ...',
          );
          savedPath = await _saveBytesViaSystemPicker(
            bytes: Uint8List.fromList(response.data ?? const <int>[]),
            fileName: fileName,
          );
        } else {
          var lastProgressReport = 0.0;
          var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
          await apiClient.dio.download(
            resolvedDownloadUrl,
            targetPath!,
            onReceiveProgress: (received, total) {
              final ratio = total <= 0
                  ? 0.0
                  : (received / total).clamp(0, 1).toDouble();
              final overallProgress = 0.12 + (ratio * 0.72);
              final now = DateTime.now();
              final shouldReport =
                  ratio >= 1 ||
                  (overallProgress - lastProgressReport).abs() >= 0.03 ||
                  now.difference(lastProgressAt) >=
                      const Duration(milliseconds: 650);
              if (!shouldReport) {
                return;
              }
              lastProgressReport = overallProgress;
              lastProgressAt = now;
              unawaited(
                _emitIncomingFileProgress(
                  jobId,
                  stage: 'downloading',
                  progress: overallProgress,
                  message: total > 0
                      ? 'جاري تنزيل الملف على الموبايل ${(ratio * 100).toStringAsFixed(0)}%'
                      : 'جاري تنزيل الملف على الموبايل...',
                ),
              );
            },
          );
          await _emitIncomingFileProgress(
            jobId,
            stage: 'saving',
            progress: 0.92,
            message: 'تم تنزيل الملف، جارٍ إنهاء الحفظ...',
          );
          savedPath = targetPath;
        }
      } else {
        throw Exception('مصدر الملف غير صالح.');
      }
      success = true;
      resultMessage = 'تم حفظ الملف الوارد على الموبايل.';

      await _emitIncomingFileProgress(
        jobId,
        stage: 'completed',
        progress: 1,
        message: 'اكتمل حفظ الملف على الموبايل.',
        savedPath: savedPath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              useSystemSaveDialog
                  ? 'تم حفظ الملف في المكان الذي اخترته.'
                  : 'تم حفظ الملف في: ${p.dirname(savedPath)}',
            ),
          ),
        );
      }
    } catch (error) {
      final cancelled = error.toString().contains('تم إلغاء حفظ الملف');
      resultMessage = cancelled
          ? 'تم إلغاء حفظ الملف على الموبايل.'
          : (error.toString().trim().isEmpty
                ? 'فشل حفظ الملف الوارد على الموبايل.'
                : error.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cancelled ? resultMessage : 'فشل استقبال الملف: $resultMessage',
            ),
          ),
        );
      }
    } finally {
      ref.read(chatSocketServiceProvider).emitEvent('file_receive_result', {
        'jobId': jobId,
        'success': success,
        'message': resultMessage,
        'savedPath': savedPath,
      });
    }
  }

  Future<void> _emitIncomingFileProgress(
    String jobId, {
    required String stage,
    required double progress,
    required String message,
    String? savedPath,
  }) async {
    ref.read(chatSocketServiceProvider).emitEvent('file_receive_progress', {
      'jobId': jobId,
      'stage': stage,
      'progress': progress.clamp(0, 1),
      'message': message,
      if (savedPath != null && savedPath.trim().isNotEmpty)
        'savedPath': savedPath,
    });
  }

  String _resolveTransferDownloadUrl(String baseUrl, String url) {
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      return url;
    }
    if (parsed.hasScheme && parsed.hasAuthority) {
      return parsed.toString();
    }
    return Uri.parse(baseUrl).resolveUri(parsed).toString();
  }

  Future<String> _saveBytesViaSystemPicker({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final savedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر مكان حفظ الملف',
      fileName: fileName,
      bytes: bytes,
    );
    if (savedPath == null || savedPath.trim().isEmpty) {
      throw Exception('تم إلغاء حفظ الملف.');
    }
    return savedPath.trim();
  }

  Future<Directory> _resolveIncomingFallbackDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      p.join(documents.path, 'iSmart Messenger', 'Storage', 'Incoming'),
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

  Future<_IncomingFileSaveTarget?> _showIncomingFileSaveDialog({
    required String fileName,
    required int fileSizeBytes,
    required String defaultDirectoryPath,
  }) {
    return showDialog<_IncomingFileSaveTarget>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('استلام ملف جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اسم الملف: $fileName'),
            const SizedBox(height: 6),
            Text('الحجم: ${formatFileSize(fileSizeBytes)}'),
            const SizedBox(height: 10),
            Text(
              'المجلد الافتراضي:\n$defaultDirectoryPath',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Text(
              'مهم: لو اخترت "اختيار المكان" فسيبدأ الاستلام أولًا، وبعد اكتمال التنزيل سيظهر لك حفظ النظام لاختيار المكان النهائي.',
              style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(dialogContext).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_IncomingFileSaveTarget.cancel),
            child: const Text('إلغاء'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_IncomingFileSaveTarget.chooseLocation),
            child: const Text('اختيار المكان'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_IncomingFileSaveTarget.quickSaveDefault),
            child: const Text('حفظ سريع'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeUpdateAgent() async {
    await _updateAgent.initialize();

    // Listen for update events
    if (!mounted) return;
    _updateAgent.events.listen((event) {
      if (!mounted) return;

      if (event.type == 'update_forced' && event.release != null) {
        _showUpdateDialog(
          release: event.release!,
          task: event.task,
          deviceUid: event.deviceUid,
          isMandatory: true,
        );
      } else if (event.type == 'update_available' && event.release != null) {
        _showUpdateDialog(
          release: event.release!,
          task: event.task,
          deviceUid: event.deviceUid,
          isMandatory: false,
        );
      }
    });
  }

  void _showUpdateDialog({
    required MobileUpdateRelease release,
    MobileUpdateTask? task,
    String? deviceUid,
    required bool isMandatory,
  }) {
    if (_isUpdateDialogOpen) {
      return;
    }
    _isUpdateDialogOpen = true;
    UpdateDialog.show(
      context,
      release: release,
      task: task,
      deviceUid: deviceUid,
      isMandatory: isMandatory,
      onUpdate: () {
        debugPrint('User agreed to update');
      },
      onLater: isMandatory
          ? null
          : () {
              debugPrint('User deferred update');
            },
    ).whenComplete(() {
      _isUpdateDialogOpen = false;
    });
  }

  @override
  void dispose() {
    _authSubscription?.close();
    _socketEventsSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _notificationTapSubscription?.cancel();
    _pushOpenedSubscription?.cancel();
    _androidShareSubscription?.cancel();
    _connectionEstablishTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _updateAgent.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final user = ref.read(authControllerProvider).valueOrNull;
    final isVisible = state == AppLifecycleState.resumed;
    _setChatVisibility(isVisible);
    if (user == null) {
      return;
    }

    final socket = ref.read(chatSocketServiceProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        // Re-establishing after background — suppress banners until socket
        // reconnects or health check succeeds (event-driven, no fixed timer).
        _markConnectionEstablishing();
        socket.setPresenceOnline();
        unawaited(_refreshSessionAndSocketAfterResume());
        unawaited(_syncPendingUploadsInBackground());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        socket.setPresenceIdle();
        break;
      case AppLifecycleState.detached:
        socket.setPresenceOffline();
        socket.disconnect();
        break;
    }
  }

  Future<void> _refreshSessionAndSocketAfterResume() async {
    try {
      await ref.read(authRepositoryProvider).getValidToken();
    } catch (_) {}
    if (!mounted) {
      return;
    }
    try {
      await _ensureSocketConnected();
    } catch (_) {}
    try {
      ref.read(chatOverviewControllerProvider.notifier).refresh(showLoader: false);
    } catch (_) {}
    final activeId = ref.read(activeConversationIdProvider);
    if (activeId != null && activeId.isNotEmpty) {
      try {
        ref.read(conversationMessagesControllerProvider(activeId).notifier).refresh();
      } catch (_) {}
    }
    unawaited(_drainChatOutbox());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final syncBanner = ref.watch(syncBannerStateProvider);
    final serverState = ref.watch(serverConnectionControllerProvider);
    switch (authState.status) {
      case AuthStatus.initializing:
        if (_lastPresenceUserId != null) {
          ref.watch(chatRealtimeControllerProvider);
          return const Stack(
            children: [
              ChatHomeScreen(),
              GlobalAnnouncementOverlay(),
            ],
          );
        }
        return const LoadingView(message: 'جارٍ التحقق من الجلسة...');
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.authenticated:
        final user = authState.user!;
        _publishDirectShareTargets(
          ref.read(chatOverviewControllerProvider).valueOrNull?.conversations ??
              const [],
        );
        ref.watch(chatRealtimeControllerProvider);
        return const Stack(
          children: [
            ChatHomeScreen(),
            GlobalAnnouncementOverlay(),
          ],
        );
    }
  }
}

class _ConnectionAlertBanner extends StatelessWidget {
  const _ConnectionAlertBanner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerRecoveryBar extends StatelessWidget {
  const _ServerRecoveryBar({
    required this.message,
    required this.onRetry,
    required this.onChangeServer,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onChangeServer;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Material(
          elevation: 14,
          color: const Color(0xFF7F1D1D),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onChangeServer,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                        ),
                        icon: const Icon(Icons.settings_ethernet, size: 18),
                        label: const Text('تغيير الرابط'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF7F1D1D),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('إعادة الاتصال'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerUnavailableDialog extends StatelessWidget {
  const _ServerUnavailableDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Card(
                  elevation: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          color: Color(0xFFB42318),
                          size: 42,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'الخادم غير متاح حاليا',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(message, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'سيتم تحديث الصفحات عند استعادة الاتصال.',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
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
  }
}

class GlobalAnnouncementOverlay extends ConsumerStatefulWidget {
  const GlobalAnnouncementOverlay({super.key});

  @override
  ConsumerState<GlobalAnnouncementOverlay> createState() =>
      _GlobalAnnouncementOverlayState();
}

class _GlobalAnnouncementOverlayState
    extends ConsumerState<GlobalAnnouncementOverlay> {
  bool _isCollapsed = false;
  int _currentIndex = 0;
  String? _lastAnnouncementIdsString;
  double? _dragX;
  double? _dragY;

  Color _toneColor(BuildContext context, String tone) {
    final scheme = Theme.of(context).colorScheme;
    return switch (tone) {
      'success' => const Color(0xFF10B981),
      'warning' => const Color(0xFFF59E0B),
      'critical' => scheme.error,
      _ => scheme.primary,
    };
  }

  Widget _buildPaginationButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1.0,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          iconSize: 14,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(icon, color: color),
          onPressed: onPressed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(announcementsControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return state.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (announcements) {
        final active = announcements.where((a) => a.isActive).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (active.isEmpty) {
          return const SizedBox.shrink();
        }

        final activeIds = active.map((a) => a.id).join(',');
        if (_lastAnnouncementIdsString != activeIds) {
          _lastAnnouncementIdsString = activeIds;
          _isCollapsed = false;
          _currentIndex = 0;
        }

        _currentIndex = _currentIndex.clamp(0, active.length - 1);
        final announcement = active[_currentIndex];
        final color = _toneColor(context, announcement.tone);

        if (_isCollapsed) {
          final screenWidth = MediaQuery.of(context).size.width;
          final screenHeight = MediaQuery.of(context).size.height;
          final defaultX = screenWidth - 16 - 40;
          final defaultY = screenHeight - 100 - 40;

          return Positioned(
            left: _dragX ?? defaultX,
            top: _dragY ?? defaultY,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _dragX = ((_dragX ?? defaultX) + details.delta.dx).clamp(
                    0.0,
                    screenWidth - 48,
                  );
                  _dragY = ((_dragY ?? defaultY) + details.delta.dy).clamp(
                    0.0,
                    screenHeight - 80,
                  );
                });
              },
              child: FloatingActionButton.small(
                heroTag: 'announcement_badge_mobile',
                backgroundColor: isDark
                    ? const Color(0xFF1E293B)
                    : Colors.white,
                foregroundColor: color,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: color.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _isCollapsed = false;
                  });
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      announcement.isPinned
                          ? Icons.push_pin_rounded
                          : Icons.campaign_rounded,
                      size: 20,
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFD32F2F),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Center(
                          child: Text(
                            '${active.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Positioned(
          top: 95,
          left: 16,
          right: 16,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(16),
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            shadowColor: Colors.black.withValues(alpha: 0.16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                color: color.withValues(alpha: 0.08),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    announcement.isPinned
                        ? Icons.push_pin_outlined
                        : Icons.campaign_outlined,
                    color: color,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          announcement.title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          announcement.message,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isDark ? Colors.white70 : Colors.black54,
                                height: 1.35,
                              ),
                        ),
                        if (active.length > 1) ...[
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              _buildPaginationButton(
                                context,
                                icon: Icons.chevron_right_rounded,
                                onPressed: _currentIndex < active.length - 1
                                    ? () => setState(() => _currentIndex++)
                                    : null,
                                color: color,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                child: Text(
                                  '${_currentIndex + 1} من ${active.length}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                ),
                              ),
                              _buildPaginationButton(
                                context,
                                icon: Icons.chevron_left_rounded,
                                onPressed: _currentIndex > 0
                                    ? () => setState(() => _currentIndex--)
                                    : null,
                                color: color,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    onPressed: () {
                      setState(() {
                        _isCollapsed = true;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Telegram-style share bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ShareBottomSheet extends ConsumerStatefulWidget {
  const _ShareBottomSheet({
    required this.content,
    required this.conversations,
    required this.currentUserId,
    required this.onSelected,
  });

  final AndroidSharedContent content;
  final List<ChatConversation> conversations;
  final String currentUserId;
  final Future<void> Function(ChatConversation) onSelected;

  @override
  ConsumerState<_ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends ConsumerState<_ShareBottomSheet> {
  String _query = '';

  bool _isImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(ext);
  }

  List<ChatConversation> get _filtered {
    List<ChatConversation> base = widget.conversations;
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      base = base
          .where(
            (c) =>
                c.displayTitle(widget.currentUserId).toLowerCase().contains(q),
          )
          .toList();
    }
    final selfChats =
        base.where((c) => c.isSelfChat(widget.currentUserId)).toList();
    final otherChats =
        base.where((c) => !c.isSelfChat(widget.currentUserId)).toList();
    return [...selfChats, ...otherChats];
  }

  bool get _hasSelfChatInList =>
      widget.conversations.any((c) => c.isSelfChat(widget.currentUserId));

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final handleColor =
        isDark ? Colors.white24 : Colors.black.withOpacity(0.12);

    final paths = widget.content.paths;
    final hasPaths = paths.isNotEmpty;
    final hasText = widget.content.text.trim().isNotEmpty;
    final allImages = hasPaths && paths.every(_isImage);

    final titleText = hasPaths
        ? (allImages
            ? 'مشاركة ${paths.length} ${paths.length == 1 ? 'صورة' : 'صور'}'
            : 'مشاركة ${paths.length} ${paths.length == 1 ? 'ملف' : 'ملفات'}')
        : 'مشاركة نص ومحتوى';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Drag handle ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: handleColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleText,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 17),
                    ),

                    // ── Preview of shared content ──────────────────────────────
                    if (allImages) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: paths.length > 4 ? 5 : paths.length,
                          itemBuilder: (_, i) {
                            if (i == 4 && paths.length > 4) {
                              return Padding(
                                padding:
                                    const EdgeInsetsDirectional.only(end: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    children: [
                                      Image.file(
                                        File(paths[i]),
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                      ),
                                      Positioned.fill(
                                        child: Container(
                                          color: Colors.black54,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '+${paths.length - 4}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return Padding(
                              padding:
                                  const EdgeInsetsDirectional.only(end: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(
                                  File(paths[i]),
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ] else if (hasPaths) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: paths.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final p = paths[i];
                            final fileName = p.split(Platform.pathSeparator).last;
                            final isImg = _isImage(p);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isImg
                                        ? Icons.image_rounded
                                        : Icons.insert_drive_file_rounded,
                                    size: 18,
                                    color: const Color(0xFF007AFF),
                                  ),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 140),
                                    child: Text(
                                      fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    // ── Text Preview ──────────────────────────────────────────
                    if (hasText) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : Colors.black.withOpacity(0.06),
                          ),
                        ),
                        child: Text(
                          widget.content.text.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],

                    // ── Search bar ────────────────────────────────────────────
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        hintText: 'البحث عن محادثة...',
                        hintStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 15,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withOpacity(0.06)
                            : Colors.black.withOpacity(0.04),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Conversation list ───────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: (!_hasSelfChatInList && _query.isEmpty)
                      ? _filtered.length + 1
                      : _filtered.length,
                  itemBuilder: (_, index) {
                    // Pinned Saved Messages quick button if not in list yet
                    if (!_hasSelfChatInList && _query.isEmpty && index == 0) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFF5856D6), Color(0xFF007AFF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(
                            Icons.bookmark_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        title: const Text(
                          'الرسائل المحفوظة (أنت)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: const Text(
                          'مساحتك السحابية لحفظ الملاحظات والملفات',
                          style: TextStyle(
                            color: Color(0xFF5856D6),
                            fontSize: 13,
                          ),
                        ),
                        onTap: () async {
                          final conv = await ref
                              .read(chatOverviewControllerProvider.notifier)
                              .openOrCreateSavedMessages(widget.currentUserId);
                          widget.onSelected(conv);
                        },
                      );
                    }

                    final realIndex = (!_hasSelfChatInList && _query.isEmpty)
                        ? index - 1
                        : index;
                    final conv = _filtered[realIndex];
                    final isSelf = conv.isSelfChat(widget.currentUserId);
                    final avatarUrl = _AuthGateState._getConversationAvatarUrl(
                      conv,
                      widget.currentUserId,
                    );
                    final letter = _AuthGateState._avatarLetter(
                      conv,
                      widget.currentUserId,
                    );
                    final title = _AuthGateState._getConversationTitle(
                      conv,
                      widget.currentUserId,
                    );
                    final subtitle = _AuthGateState._getConversationSubtitle(
                      conv,
                      widget.currentUserId,
                    );

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: isSelf
                          ? Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF5856D6),
                                    Color(0xFF007AFF),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.bookmark_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            )
                          : ChatAvatar(
                              radius: 24,
                              backgroundColor: colorScheme.primaryContainer,
                              avatarUrl: avatarUrl,
                              fallback: Text(
                                letter,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        subtitle,
                        style: TextStyle(
                          color: isSelf
                              ? const Color(0xFF5856D6)
                              : Colors.grey.shade600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => widget.onSelected(conv),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


class _ChangeServerBaseUrlDialog extends StatefulWidget {
  const _ChangeServerBaseUrlDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ChangeServerBaseUrlDialog> createState() =>
      _ChangeServerBaseUrlDialogState();
}

class _ChangeServerBaseUrlDialogState
    extends State<_ChangeServerBaseUrlDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تغيير رابط الخادم'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'API Base URL',
          hintText: 'http://192.168.1.10:5000',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('__reset__'),
          child: const Text('الافتراضي'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('حفظ ومحاولة الاتصال'),
        ),
      ],
    );
  }
}
