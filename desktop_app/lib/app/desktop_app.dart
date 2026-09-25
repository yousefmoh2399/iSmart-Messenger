import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:lottie/lottie.dart';

import '../core/config/app_config.dart';
import '../core/settings/user_preferences.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/chat/data/chat_socket_service.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../shared/providers/providers.dart';
import '../shared/services/desktop_update_agent.dart'
    if (dart.library.html) '../shared/services/desktop_update_agent_web.dart';
import '../shared/services/lan_file_transfer_service.dart';
import '../shared/services/print_job_processor.dart';
import '../shared/services/web_platform_bridge.dart' as web_bridge;
import '../shared/widgets/loading_indicator.dart';
import 'desktop_workspace_shell.dart';


class WorkplaceDesktopApp extends ConsumerWidget {
  const WorkplaceDesktopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(appBootstrapProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final effectiveWindowTheme =
        themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system &&
                platformBrightness == Brightness.dark)
        ? 'dark'
        : 'light';
    unawaited(web_bridge.setElectronWindowTheme(effectiveWindowTheme));

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "iSmart Messenger",
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        if (web_bridge.isElectron()) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 34),
                  child: child ?? const SizedBox.shrink(),
                ),
              ],
            ),
          );
        }
        return child ?? const SizedBox.shrink();
      },
      home: bootstrap.when(
        loading: () =>
            const _LoadingScreen(message: 'جارٍ تجهيز تطبيق سطح المكتب...'),
        error: (error, stackTrace) => _AuthGate(
          initialErrorMessage:
              'فشل تهيئة التطبيق. افتح إعدادات الخادم ثم حاول مرة أخرى.\n${error.toString()}',
          openServerSettingsOnStart: true,
        ),
        data: (status) {
          if (status == BootstrapStatus.failed) {
            return const _AuthGate(
              initialErrorMessage:
                  'فشل تهيئة التطبيق. افتح إعدادات الخادم ثم حاول مرة أخرى.',
              openServerSettingsOnStart: true,
            );
          }
          return const _AuthGate();
        },
      ),
    );
  }
}

class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate({
    this.initialErrorMessage,
    this.openServerSettingsOnStart = false,
  });

  final String? initialErrorMessage;
  final bool openServerSettingsOnStart;

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate>
    with WidgetsBindingObserver {
  static const MethodChannel _windowChannel = MethodChannel('dbacd_hub/window');
  String? _lastPresenceUserId;
  StreamSubscription<ChatSocketEvent>? _desktopEventsSubscription;
  StreamSubscription<DesktopUpdateEvent>? _updateAgentEventsSubscription;
  StreamSubscription<LanIncomingTransferRequest>? _lanIncomingSubscription;
  StreamSubscription<LanTransferProgressEvent>? _lanProgressSubscription;
  ProviderSubscription<AsyncValue<UserPreferences>>? _preferencesSubscription;
  ProviderSubscription<AuthState>? _authSubscription;
  String? _updateAgentUserId;
  bool _isUpdateInProgress = false;
  String _updateStatusMessage = '';
  int _updateProgress = 0;

  bool get _hasDesktopCapabilities => !kIsWeb || web_bridge.isElectron();
  bool _isUpdateDialogMinimized = false;
  bool _isPendingRestart = false;
  String? _lastConnectionErrorMessage;
  bool _serverRefreshInFlight = false;
  bool _hasConfirmedServerDisconnect = false;
  bool _serverRestoreRefreshInFlight = false;
  int _serverFailureStreak = 0;
  bool _lastKnownWindowVisible = true;
  bool _lastKnownWindowMinimized = false;

  // Event-driven connection flag.
  // True while the app is still establishing/re-establishing its connection.
  // Suppresses false-positive server-unavailable banners during startup and
  // window restore transitions.
  // Cleared as soon as the socket reports connected or a health-check succeeds.
  // A 30-second fallback timer surfaces genuine outages if neither fires.
  bool _isEstablishingConnection = true;
  Timer? _connectionEstablishTimer;
  static const _connectionEstablishTimeoutDuration = Duration(seconds: 30);

  Future<void> _restartPreparedUpdate() async {
    try {
      await ref.read(desktopUpdateAgentProvider).restartToApplyPreparedUpdate();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _retryFailedUpdate() async {
    try {
      await ref.read(desktopUpdateAgentProvider).retryFailedUpdate();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _setChatVisibility(bool isVisible) {
    final current = ref.read(chatAppVisibilityProvider);
    if (current == isVisible) {
      return;
    }
    ref.read(chatAppVisibilityProvider.notifier).state = isVisible;
  }

  Future<void> _syncWindowVisibilityState({bool updatePresence = true}) async {
    if (!mounted) {
      return;
    }

    try {
      dynamic result;
      if (kIsWeb && web_bridge.isElectron()) {
        result = await web_bridge.getElectronWindowState();
      } else {
        result = await _windowChannel.invokeMethod<dynamic>('getWindowState');
      }
      if (!mounted || result is! Map) {
        return;
      }

      final map = Map<Object?, Object?>.from(result);
      final isVisible = map['isVisible'] == true;
      final isMinimized = map['isMinimized'] == true;
      final isForeground = map['isForeground'] == true;
      final isChatVisible = isVisible && !isMinimized;
      final wasUnavailable =
          !_lastKnownWindowVisible || _lastKnownWindowMinimized;
      final restoredFromMinimized = wasUnavailable && isChatVisible;
      _lastKnownWindowVisible = isVisible;
      _lastKnownWindowMinimized = isMinimized;
      if (restoredFromMinimized) {
        _markConnectionEstablishing();
      }

      _setChatVisibility(isChatVisible);

      if (!updatePresence) {
        return;
      }

      final user = ref.read(currentUserProvider);
      if (user == null) {
        return;
      }

      _setPresenceStatus(isChatVisible && isForeground ? 'online' : 'idle');
    } catch (_) {}
  }

  void _handleAuthStatusChange(AuthState auth) {
    if (!mounted) {
      return;
    }
    if (auth.status == AuthStatus.unauthenticated) {
      _lastPresenceUserId = null;
      _lastConnectionErrorMessage = null;
      _updateAgentUserId = null;
      _isEstablishingConnection = true;
      _connectionEstablishTimer?.cancel();
      _isUpdateInProgress = false;
      _isUpdateDialogMinimized = false;
      _isPendingRestart = false;
      _updateStatusMessage = '';
      _updateProgress = 0;
      if (_hasDesktopCapabilities) {
        ref.read(desktopUpdateAgentProvider).stop();
      }
      if (!kIsWeb) {
        unawaited(ref.read(lanFileTransferServiceProvider).stop());
      }
      _setTrayStatus('offline');
      _setChatVisibility(false);
      ref.read(chatSocketServiceProvider).disconnect();
      return;
    }

    if (auth.status == AuthStatus.authenticated) {
      final user = auth.user!;
      if (_lastPresenceUserId != user.id) {
        _lastPresenceUserId = user.id;
        unawaited(_syncWindowVisibilityState());
      }
      if (_updateAgentUserId != user.id) {
        _updateAgentUserId = user.id;
        if (_hasDesktopCapabilities) {
          ref.read(desktopUpdateAgentProvider).start(user);
        }
      }
      unawaited(_syncAdminServerDefaults());
      _markConnectionEstablishing();
      unawaited(_refreshServerConnectionState());
      if (!kIsWeb) {
        unawaited(_ensureLanTransferServiceRunning());
      }
    }
  }

  Future<void> _syncAdminServerDefaults() async {
    try {
      final defaults = await ref
          .read(appSettingsServiceProvider)
          .fetchDefaults();
      final desktopUrl = defaults.desktopBaseUrl?.trim();
      if (desktopUrl == null || desktopUrl.isEmpty) {
        return;
      }
      await ref
          .read(apiBaseUrlControllerProvider.notifier)
          .applyAdminDefault(desktopUrl);
      await ref.read(serverConnectionControllerProvider.notifier).refresh();
    } catch (_) {}
  }

  /// Marks the app as actively connecting/re-connecting.
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
  void _markConnectionEstablished() {
    if (!mounted) return;
    _isEstablishingConnection = false;
    _connectionEstablishTimer?.cancel();
  }

  Future<void> _refreshServerConnectionState({
    bool recoverVisibleDisconnect = true,
    bool quiet = false,
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
          .refresh(
            preserveConnectedStateOnFailure: quiet || _isEstablishingConnection,
          );
    } finally {
      _serverRefreshInFlight = false;
    }
    if (!mounted) {
      return;
    }
    if (!result.isConnected) {
      if (quiet || _isEstablishingConnection) {
        return;
      }
      _serverFailureStreak++;
      if (_serverFailureStreak >= 2) {
        _hasConfirmedServerDisconnect = true;
        setState(() {});
        _showConnectionSnackBar(
          _buildServerUnavailableMessage(result.message),
          isError: true,
        );
      }
      return;
    }
    // Connection confirmed — clear establishing flag immediately.
    _markConnectionEstablished();
    if (_hasConfirmedServerDisconnect) {
      if (quiet || !recoverVisibleDisconnect) {
        _hasConfirmedServerDisconnect = false;
        _lastConnectionErrorMessage = null;
      } else {
        unawaited(_refreshDataAfterServerRestored());
        _showConnectionSnackBar('تمت استعادة الاتصال بالخادم.', isError: false);
      }
    } else if (_lastConnectionErrorMessage != null) {
      // A transient/minimized-window probe failed earlier. Clear the stale
      // warning silently; do not reload the workspace or show a success toast.
      _lastConnectionErrorMessage = null;
    }
    _hasConfirmedServerDisconnect = false;
    _lastConnectionErrorMessage = null;
    _serverFailureStreak = 0;
    setState(() {});
  }

  Future<void> _refreshDataAfterServerRestored() async {
    if (_serverRestoreRefreshInFlight) {
      return;
    }
    _serverRestoreRefreshInFlight = true;
    try {
      ref.read(serverRecoveryRevisionProvider.notifier).state++;
      ref.invalidate(chatSocketConnectionProvider);
      try {
        await ref.read(authControllerProvider.notifier).refreshCurrentUser();
      } catch (_) {}
      if (!mounted) {
        return;
      }
      unawaited(_ensureLanTransferServiceRunning());
    } finally {
      _serverRestoreRefreshInFlight = false;
    }
  }

  void _showConnectionSnackBar(String message, {required bool isError}) {
    if (!mounted) {
      return;
    }
    if (isError) {
      if (_isEstablishingConnection) {
        return;
      }
      if (_lastConnectionErrorMessage == message) {
        return;
      }
      _lastConnectionErrorMessage = message;
    } else {
      _lastConnectionErrorMessage = null;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? const Color(0xFFB42318) : null,
          content: Text(message),
        ),
      );
  }

  String _buildServerUnavailableMessage(String details) {
    final trimmed = details.trim();
    if (trimmed.isEmpty) {
      return 'الخادم غير متاح الآن. تحقق من الشبكة أو من حالة السيرفر ثم أعد المحاولة.';
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
    final controller = TextEditingController(text: currentBaseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير رابط الخادم'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'http://192.168.1.10:5000',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('__reset__'),
            child: const Text('الافتراضي'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('حفظ ومحاولة الاتصال'),
          ),
        ],
      ),
    );
    controller.dispose();
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

    await ref.read(authRepositoryProvider).clearLocalSessionForServerChange();
    ref.read(serverRecoveryRevisionProvider.notifier).state++;
    ref.invalidate(authControllerProvider);
    ref.invalidate(documentsControllerProvider);
    ref.invalidate(adminDocumentsControllerProvider);
    ref.invalidate(usersControllerProvider);
    ref.invalidate(ticketsControllerProvider);
    ref.invalidate(printerControllerProvider);
    await _retryServerConnection();
  }

  @override
  void initState() {
    super.initState();
    // Start in connecting state — suppresses false-positive banners on startup.
    _markConnectionEstablishing();
    WidgetsBinding.instance.addObserver(this);
    _windowChannel.setMethodCallHandler(_onWindowMethodCall);
    if (kIsWeb && web_bridge.isElectron()) {
      web_bridge.setElectronTrayActionHandler((action) {
        unawaited(_handleTrayAction(<String, String>{'action': action}));
      });
    }
    _listenToDesktopEvents();
    _listenToUpdateAgentEvents();
    _listenToLanTransfers();
    _preferencesSubscription = ref.listenManual<AsyncValue<UserPreferences>>(
      userPreferencesControllerProvider,
      (_, next) {
        if (next.hasValue) {
          _publishDesktopStorageConfig();
        }
      },
    );
    _authSubscription = ref.listenManual<AuthState>(
      authControllerProvider,
      (_, next) => _handleAuthStatusChange(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _desktopEventsSubscription?.cancel();
    _updateAgentEventsSubscription?.cancel();
    _lanIncomingSubscription?.cancel();
    _lanProgressSubscription?.cancel();
    _authSubscription?.close();
    try {
      ref.read(desktopUpdateAgentProvider).stop();
      unawaited(ref.read(lanFileTransferServiceProvider).stop());
    } catch (e) {
      // Widget was disposed, cannot access ref
    }
    _preferencesSubscription?.close();
    _connectionEstablishTimer?.cancel();
    _windowChannel.setMethodCallHandler(null);
    if (kIsWeb && web_bridge.isElectron()) {
      web_bridge.setElectronTrayActionHandler(null);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    try {
      if (!mounted) return;
      final user = ref.read(currentUserProvider);
      if (user == null) {
        return;
      }
      final isElectronWeb = kIsWeb && web_bridge.isElectron();

      switch (state) {
        case AppLifecycleState.resumed:
          _markConnectionEstablishing();
          await _syncWindowVisibilityState();
          if (!isElectronWeb) {
            unawaited(
              Future<void>.delayed(const Duration(milliseconds: 800), () async {
                if (!mounted) {
                  return;
                }
                await _refreshServerConnectionState(
                  recoverVisibleDisconnect: false,
                  quiet: true,
                );
              }),
            );
          }
          break;
        case AppLifecycleState.inactive:
          await _syncWindowVisibilityState();
          break;
        case AppLifecycleState.hidden:
        case AppLifecycleState.paused:
          if (isElectronWeb) {
            await _syncWindowVisibilityState();
          } else {
            _setChatVisibility(false);
            _setPresenceStatus('idle');
          }
          break;
        case AppLifecycleState.detached:
          _setChatVisibility(false);
          _setPresenceStatus('offline');
          if (mounted) {
            ref.read(chatSocketServiceProvider).disconnect();
          }
          break;
      }
    } catch (e) {
      // Widget was disposed, ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final serverState = ref.watch(serverConnectionControllerProvider);

    switch (auth.status) {
      case AuthStatus.initializing:
        return const _LoadingScreen(message: 'جارٍ التحقق من الجلسة...');
      case AuthStatus.unauthenticated:
        return LoginScreen(
          initialErrorMessage:
              widget.initialErrorMessage ??
              (auth.error != null ? auth.error.toString() : null),
          openServerSettingsOnStart: widget.openServerSettingsOnStart,
        );
      case AuthStatus.authenticated:
        ref.watch(chatSocketConnectionProvider);
        ref.watch(chatRealtimeControllerProvider);
        final serverConnection = serverState.valueOrNull;
        final showServerBanner =
            _hasConfirmedServerDisconnect &&
            serverConnection != null &&
            !serverConnection.isConnected;
        return Stack(
          children: [
            const DesktopWorkspaceShell(),
            const GlobalAnnouncementOverlay(),
            if (showServerBanner)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: SafeArea(
                  bottom: false,
                  child: _ServerStatusBanner(
                    message: _buildServerUnavailableMessage(
                      serverConnection.message,
                    ),
                  ),
                ),
              ),
            if (showServerBanner)
              _ServerRecoveryBar(
                message: _buildServerUnavailableMessage(
                  serverConnection.message,
                ),
                onRetry: _retryServerConnection,
                onChangeServer: _changeServerBaseUrl,
              ),
            if (_isUpdateInProgress && !_isUpdateDialogMinimized)
              _UpdateProgressOverlay(
                message: _updateStatusMessage,
                progress: _updateProgress,
                isPendingRestart: _isPendingRestart,
                onMinimize: () {
                  setState(() => _isUpdateDialogMinimized = true);
                },
                onRestartNow: _isPendingRestart ? _restartPreparedUpdate : null,
              ),
            if (_isUpdateInProgress && _isUpdateDialogMinimized)
              Positioned(
                bottom: 12,
                left: 12,
                child: _UpdateProgressBanner(
                  message: _updateStatusMessage,
                  progress: _updateProgress,
                  isPendingRestart: _isPendingRestart,
                  onTap: () {
                    setState(() => _isUpdateDialogMinimized = false);
                  },
                  onRestartNow: _isPendingRestart
                      ? _restartPreparedUpdate
                      : null,
                ),
              ),
          ],
        );
    }
  }

  Future<dynamic> _onWindowMethodCall(MethodCall call) async {
    if (call.method == 'trayAction') {
      await _handleTrayAction(call.arguments);
      return null;
    }

    if (call.method == 'windowClose') {
      if (_isUpdateInProgress) {
        if (!mounted) return null;
        final decision = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تحديث قيد التقدم'),
            content: const Text(
              'التطبيق قيد التحديث الآن. هل تريد الإغلاق الآن أم السماح للتحديث بالاستمرار في الخلفية والإغلاق لاحقاً؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('استمر التحديث لاحقاً'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('أغلق الآن'),
              ),
            ],
          ),
        );
        if (decision == false) {
          setState(() => _isUpdateDialogMinimized = true);
          return false;
        }
      }
      return null;
    }

    if (call.method != 'windowStateChanged') {
      return null;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) {
      return null;
    }

    final raw = call.arguments;
    if (raw is! Map) {
      return null;
    }

    final map = Map<Object?, Object?>.from(raw);
    final isVisible = map['isVisible'] == true;
    final isMinimized = map['isMinimized'] == true;
    final isForeground = map['isForeground'] == true;
    final isChatVisible = isVisible && !isMinimized;
    final wasUnavailable =
        !_lastKnownWindowVisible || _lastKnownWindowMinimized;
    final restoredFromMinimized = wasUnavailable && isChatVisible;
    _lastKnownWindowVisible = isVisible;
    _lastKnownWindowMinimized = isMinimized;
    if (restoredFromMinimized) {
      _markConnectionEstablishing();
    }

    _setChatVisibility(isChatVisible);
    _setPresenceStatus(isChatVisible && isForeground ? 'online' : 'idle');

    return null;
  }

  Future<void> _handleTrayAction(dynamic rawArguments) async {
    if (rawArguments is! Map) {
      return;
    }
    final arguments = Map<Object?, Object?>.from(rawArguments);
    final action = arguments['action']?.toString() ?? '';
    if (action.isEmpty) {
      return;
    }

    if (action == 'open') {
      return;
    }
    if (action == 'settings' || action == 'profile') {
      if (!mounted) {
        return;
      }
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      return;
    }
    if (action == 'signout') {
      await ref.read(authControllerProvider.notifier).logout();
      return;
    }
    if (action.startsWith('status:')) {
      final status = action.replaceFirst('status:', '').trim();
      if (status.isNotEmpty) {
        _setPresenceStatus(status, forceEmit: true);
      }
      return;
    }
    if (action.startsWith('startup_enabled:')) {
      if (!mounted) {
        return;
      }
      final enabled = action.endsWith('true');
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Startup at Windows login enabled.'
                : 'Startup at Windows login disabled.',
          ),
        ),
      );
    }
  }

  void _setPresenceStatus(String status, {bool forceEmit = false}) {
    final socket = ref.read(chatSocketServiceProvider);
    socket.setPresenceStatus(status, forceEmit: forceEmit);
    ref.read(desktopUpdateAgentProvider).setConnectionStatus(status);
    _setTrayStatus(status);
  }

  Future<void> _setTrayStatus(String status) async {
    try {
      await _windowChannel.invokeMethod<void>('setTrayStatus', {
        'status': status,
      });
    } catch (_) {}
  }

  void _listenToDesktopEvents() {
    _desktopEventsSubscription?.cancel();
    final socket = ref.read(chatSocketServiceProvider);
    _desktopEventsSubscription = socket.events.listen((event) {
      if (event.type == 'socket_connected') {
        final recoverOnSocketConnected = !(kIsWeb && web_bridge.isElectron());
        _setTrayStatus('online');
        if (_hasDesktopCapabilities) {
          _publishPrinterCatalog();
          _publishDesktopStorageConfig();
        }

        // Socket connected — server reachable, clear establishing flag immediately.
        _markConnectionEstablished();
        if (_hasConfirmedServerDisconnect && recoverOnSocketConnected) {
          unawaited(_refreshDataAfterServerRestored());
          _showConnectionSnackBar(
            'تمت استعادة الاتصال بالخادم.',
            isError: false,
          );
        } else if (_lastConnectionErrorMessage != null) {
          _lastConnectionErrorMessage = null;
        }
        _hasConfirmedServerDisconnect = false;
        _lastConnectionErrorMessage = null;
        _serverFailureStreak = 0;
        setState(() {});

        unawaited(
          _refreshServerConnectionState(
            recoverVisibleDisconnect: recoverOnSocketConnected,
            quiet: true,
          ),
        );
        return;
      }
      if (event.type == 'socket_error' || event.type == 'socket_disconnected') {
        // Ignore while still establishing — socket will retry on its own.
        if (_isEstablishingConnection) {
          return;
        }
        unawaited(_refreshServerConnectionState());
        return;
      }
      if (event.type == 'updates_updated') {
        unawaited(_refreshServerConnectionState());
        if (!kIsWeb || web_bridge.isElectron()) {
          unawaited(ref.read(desktopUpdateAgentProvider).checkNow());
        }
        return;
      }
      if (event.type == 'print_job_requested') {
        _handlePrintJob(event.payload);
        return;
      }
      if (event.type == 'printers_catalog_refresh_requested') {
        if (_hasDesktopCapabilities) {
          unawaited(_publishPrinterCatalog());
        }
        return;
      }
      if (event.type == 'file_save_requested') {
        _handleFileSaveJob(event.payload);
        return;
      }
      if (event.type == 'attachment_rehydrate_requested') {
        unawaited(
          ref
              .read(chatRepositoryProvider)
              .respondToAttachmentRehydrate(event.payload),
        );
      }
    });
  }

  void _listenToUpdateAgentEvents() {
    _updateAgentEventsSubscription?.cancel();
    _updateAgentEventsSubscription = ref
        .read(desktopUpdateAgentProvider)
        .events
        .listen((event) {
          if (!mounted) {
            return;
          }
          if (event.type == 'status') {
            setState(() {
              _isUpdateInProgress = true;
              _isPendingRestart = false;
              _updateStatusMessage = event.message;
              _updateProgress = event.progress ?? _updateProgress;
            });
            return;
          }
          if (event.type == 'ready_to_restart') {
            setState(() {
              _isUpdateInProgress = true;
              _isPendingRestart = true;
              _updateStatusMessage = event.message;
              _updateProgress = event.progress ?? 100;
            });
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  event.message.isEmpty
                      ? 'اكتمل تنزيل التحديث. يمكنك إعادة تشغيل التطبيق عندما يناسبك.'
                      : event.message,
                ),
                action: SnackBarAction(
                  label: 'إعادة التشغيل',
                  onPressed: () {
                    unawaited(_restartPreparedUpdate());
                  },
                ),
              ),
            );
            return;
          }
          if (event.type == 'completed') {
            setState(() {
              _isUpdateInProgress = false;
              _isUpdateDialogMinimized = false;
              _isPendingRestart = false;
              _updateStatusMessage = '';
              _updateProgress = 100;
            });
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  event.message.isEmpty
                      ? 'تم تثبيت التحديث بنجاح.'
                      : event.message,
                ),
              ),
            );
            return;
          }
          if (event.type == 'failed') {
            final message = event.message.trim();
            setState(() {
              _isUpdateInProgress = false;
              _isUpdateDialogMinimized = false;
              _isPendingRestart = false;
              _updateStatusMessage = '';
              _updateProgress = 0;
            });
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  message.isEmpty
                      ? 'فشل تحديث التطبيق.'
                      : 'فشل التحديث: $message',
                ),
                action: SnackBarAction(
                  label: 'إعادة المحاولة',
                  onPressed: () {
                    unawaited(_retryFailedUpdate());
                  },
                ),
              ),
            );
            return;
          }
          if (event.type == 'heartbeat_error') {
            return;
          }
        });
  }

  void _listenToLanTransfers() {
    if (kIsWeb) {
      return;
    }
    final service = ref.read(lanFileTransferServiceProvider);
    _lanIncomingSubscription?.cancel();
    _lanIncomingSubscription = service.incomingRequests.listen((request) {
      unawaited(_showLanIncomingTransferDialog(request));
    });
    _lanProgressSubscription?.cancel();
    _lanProgressSubscription = service.progressEvents.listen((event) {
      if (!mounted || event.direction != 'incoming') {
        return;
      }
      if (event.stage == 'completed') {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'تم استلام ${event.fileName} من ${event.peerIp ?? 'جهاز على الشبكة'} بنجاح.',
            ),
          ),
        );
      } else if (event.stage == 'failed') {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              event.message?.trim().isNotEmpty == true
                  ? event.message!
                  : 'فشل استقبال ملف عبر الشبكة المحلية.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _ensureLanTransferServiceRunning() async {
    try {
      await ref.read(lanFileTransferServiceProvider).start();
      await ref.read(lanFileTransferServiceProvider).refreshLocalIpv4s();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('تعذر تشغيل استقبال ملفات الشبكة المحلية: $error'),
        ),
      );
    }
  }

  Future<void> _showLanIncomingTransferDialog(
    LanIncomingTransferRequest request,
  ) async {
    if (!mounted) {
      await request.reject();
      return;
    }
    final prefs = ref.read(userPreferencesControllerProvider).valueOrNull;
    final decision = await showDialog<_LanIncomingSaveChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('استقبال ملف عبر الشبكة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المرسل: ${request.senderName}'),
            const SizedBox(height: 6),
            Text('عنوان الجهاز: ${request.senderIp}'),
            const SizedBox(height: 6),
            Text('الملف: ${request.fileName}'),
            const SizedBox(height: 6),
            Text('الحجم: ${formatFileSize(request.fileSizeBytes)}'),
            const SizedBox(height: 10),
            Text(
              'يمكنك الحفظ مباشرة في المجلد الافتراضي أو اختيار مكان مختلف لهذا الملف فقط.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            if (prefs?.scanSaveDirectoryPath?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                'سيتم الحفظ في:\n${prefs!.scanSaveDirectoryPath}',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_LanIncomingSaveChoice.reject),
            child: const Text('رفض'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_LanIncomingSaveChoice.chooseLocation),
            child: const Text('اختيار المكان'),
          ),
          if (prefs?.scanSaveDirectoryPath?.trim().isNotEmpty == true)
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_LanIncomingSaveChoice.useDefault),
              child: const Text('حفظ في الافتراضي'),
            ),
        ],
      ),
    );
    if (decision == _LanIncomingSaveChoice.useDefault) {
      await request.accept(saveDirectoryPath: prefs?.scanSaveDirectoryPath);
      return;
    }
    if (decision == _LanIncomingSaveChoice.chooseLocation) {
      final saveDirectoryPath = kIsWeb && web_bridge.isElectron()
          ? await web_bridge.pickElectronDirectory(
              title: 'اختر مجلد حفظ الملف الوارد',
              defaultPath: prefs?.scanSaveDirectoryPath,
            )
          : await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'اختر مجلد حفظ الملف الوارد',
            );
      if (saveDirectoryPath == null || saveDirectoryPath.trim().isEmpty) {
        await request.reject();
        return;
      }
      await request.accept(saveDirectoryPath: saveDirectoryPath.trim());
      return;
    }
    await request.reject();
  }

  Future<void> _publishPrinterCatalog() async {
    try {
      final catalog = await ref
          .read(desktopPrintServiceProvider)
          .getPrinterCatalog();
      await ref.read(chatSocketServiceProvider).emitWithAck('printers:update', {
        'printers': catalog.printers,
        'defaultPrinter': catalog.defaultPrinter,
      });
    } catch (_) {}
  }

  Future<void> _publishDesktopStorageConfig() async {
    try {
      final prefs = ref.read(userPreferencesControllerProvider).valueOrNull;
      await ref.read(chatSocketServiceProvider).emitWithAck(
        'desktop_storage:update',
        {'autoSaveAfterScan': prefs?.autoSaveAfterScan == true},
      );
    } catch (_) {}
  }

  Future<void> _handlePrintJob(Map<String, dynamic> payload) async {
    final prefs = ref.read(userPreferencesControllerProvider).valueOrNull;
    final processor = ref.read(printJobProcessorProvider);
    final result = await processor.process(
      payload,
      preferredPrinterName: prefs?.preferredPrinterName,
    );

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final isSuccess = result.status == PrintJobProcessStatus.submitted;
    final isDuplicate = result.status == PrintJobProcessStatus.duplicateIgnored;
    if (isDuplicate) {
      return;
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          isSuccess
              ? 'تمت طباعة الملف بنجاح.'
              : 'فشل الطباعة: ${result.message}',
        ),
      ),
    );
  }

  Future<void> _handleFileSaveJob(Map<String, dynamic> payload) async {
    final prefs = ref.read(userPreferencesControllerProvider).valueOrNull;
    final preferredDirectoryPath = _preferredDirectoryForFileSave(
      payload,
      prefs,
    );
    final result = await ref
        .read(desktopFileSaveServiceProvider)
        .executeSaveJob(
          payload,
          preferredDirectoryPath: preferredDirectoryPath,
          onProgress:
              ({
                required String stage,
                required double progress,
                required String message,
                String? savedPath,
              }) {
                ref
                    .read(chatSocketServiceProvider)
                    .emitEvent('file_save_progress', {
                      'jobId': payload['jobId']?.toString(),
                      'stage': stage,
                      'progress': progress,
                      'message': message,
                      if (savedPath != null && savedPath.trim().isNotEmpty)
                        'savedPath': savedPath,
                    });
              },
        );

    ref.read(chatSocketServiceProvider).emitEvent('file_save_result', {
      'jobId': payload['jobId']?.toString(),
      'success': result.success,
      'message': result.message,
      'savedPath': result.savedPath,
    });

    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'تم حفظ ملف جديد من الموبايل على الكمبيوتر.'
              : 'فشل حفظ الملف الوارد: ${result.message}',
        ),
      ),
    );
  }

  String? _preferredDirectoryForFileSave(
    Map<String, dynamic> payload,
    UserPreferences? prefs,
  ) {
    final source = payload['source']?.toString().trim().toLowerCase() ?? '';
    final isScanPdf =
        source.contains('scan') ||
        source == 'mobile_upload_summary_save_to_desktop' ||
        source == 'mobile_my_files_pending_transfer';

    if (isScanPdf && prefs?.scanSaveDirectoryPath?.trim().isNotEmpty == true) {
      return prefs!.scanSaveDirectoryPath!.trim();
    }

    if (prefs?.localStorageDirectoryPath?.trim().isNotEmpty == true) {
      return prefs!.localStorageDirectoryPath!.trim();
    }

    return null;
  }
}

enum _LanIncomingSaveChoice { useDefault, chooseLocation, reject }

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLoadingIndicator(size: 28),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _UpdateProgressOverlay extends StatelessWidget {
  const _UpdateProgressOverlay({
    required this.message,
    required this.progress,
    required this.isPendingRestart,
    required this.onMinimize,
    required this.onRestartNow,
  });

  final String message;
  final int progress;
  final bool isPendingRestart;
  final VoidCallback onMinimize;
  final VoidCallback? onRestartNow;

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0, 100);

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 18,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 36),
                        const Expanded(child: SizedBox()),
                        IconButton(
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: onMinimize,
                          icon: const Icon(Iconsax.close_circle),
                          tooltip: 'إخفاء التحديث',
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    /// 👇 هنا الشكل الجديد (دايرة حوالين الصورة)
                    SizedBox(
                      width: 130,
                      height: 130,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 130,
                            height: 130,
                            child: CircularProgressIndicator(
                              value: safeProgress / 100,
                              strokeWidth: 6,
                              backgroundColor: Colors.grey.shade300,
                            ),
                          ),

                          /// الصورة في النص
                          Lottie.asset(
                            'assets/json/update.json',
                            width: 80,
                            height: 80,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      isPendingRestart
                          ? 'التحديث جاهز للتثبيت'
                          : 'جاري تحديث التطبيق',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    Text(
                      message.isEmpty
                          ? isPendingRestart
                                ? 'تم تنزيل التحديث في الخلفية. يمكنك إعادة تشغيل التطبيق في الوقت المناسب لك.'
                                : 'يتم الآن تنزيل التحديث في الخلفية.'
                          : message,
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 12),

                    /// نسبة التحميل
                    Text(
                      '$safeProgress%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),

                    if (isPendingRestart && onRestartNow != null) ...[
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onRestartNow,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('إعادة التشغيل الآن'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerStatusBanner extends StatelessWidget {
  const _ServerStatusBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: const Color(0xFFB42318),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Iconsax.cloud, color: Colors.white),
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
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        top: false,
        child: Material(
          elevation: 14,
          color: const Color(0xFF7F1D1D),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Iconsax.cloud_cross, color: Colors.white),
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
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onChangeServer,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  icon: const Icon(Icons.settings_ethernet, size: 18),
                  label: const Text('تغيير الرابط'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF7F1D1D),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('إعادة الاتصال'),
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              elevation: 18,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Iconsax.cloud_cross,
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
                    const AppLoadingIndicator(size: 24),
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
    );
  }
}

class _UpdateProgressBanner extends StatelessWidget {
  const _UpdateProgressBanner({
    required this.message,
    required this.progress,
    required this.isPendingRestart,
    required this.onTap,
    required this.onRestartNow,
  });

  final String message;
  final int progress;
  final bool isPendingRestart;
  final VoidCallback onTap;
  final VoidCallback? onRestartNow;

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0, 100);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: isPendingRestart
                  ? [Colors.green.shade600, Colors.green.shade700]
                  : [Colors.blue.shade600, Colors.blue.shade700],
            ),
          ),
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isPendingRestart)
                      const Icon(
                        Icons.restart_alt,
                        color: Colors.white,
                        size: 18,
                      )
                    else
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPendingRestart ? 'ريستارت' : 'جاري التحديث',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: safeProgress / 100,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '$safeProgress%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (isPendingRestart && onRestartNow != null)
                      TextButton(
                        onPressed: onRestartNow,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'إعادة التشغيل',
                          style: TextStyle(fontSize: 10),
                        ),
                      )
                    else
                      const Text(
                        'انقر للعودة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
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
  Offset _collapsedOffset = Offset.zero;
  Offset _expandedOffset = Offset.zero;

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
          return Positioned(
            right: 24 - _collapsedOffset.dx,
            bottom: 24 - _collapsedOffset.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _collapsedOffset += details.delta;
                });
              },
              child: FloatingActionButton.small(
                heroTag: 'announcement_badge_desktop',
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
          top: 60 + _expandedOffset.dy,
          right: 24 - _expandedOffset.dx,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _expandedOffset += details.delta;
              });
            },
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              shadowColor: Colors.black.withValues(alpha: 0.16),
              child: Container(
                width: 380,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 150),
                            child: SingleChildScrollView(
                              child: Text(
                                announcement.message,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                      height: 1.35,
                                    ),
                              ),
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
          ),
        );
      },
    );
  }
}
