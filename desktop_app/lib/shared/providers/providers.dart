import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_base_url_store.dart';
import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/media_url_resolver.dart';
import '../../core/settings/user_preferences.dart';
import '../../core/settings/user_preferences_store.dart';
import '../../core/theme/theme_mode_store.dart';
import '../../features/admin/data/announcement_repository.dart';
import '../../features/admin/data/backup_repository.dart';
import '../../features/admin/data/update_management_repository.dart';
import '../../features/admin/presentation/announcements_controller.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/auth_session_manager.dart';
import '../../features/auth/data/session_store.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/data/chat_socket_service.dart';
import '../../features/chat/models/chat_models.dart';
import '../../features/chat/presentation/chat_overview_controller.dart';
import '../../features/chat/presentation/chat_realtime_controller.dart';
import '../../features/files/data/document_repository.dart';
import '../../features/files/presentation/documents_controller.dart';
import '../../features/it_assets/data/it_assets_repository.dart';
import '../../features/printers/data/printer_repository.dart';
import '../../features/printers/models/printer_models.dart';
import '../../features/printers/presentation/printer_controller.dart';
import '../../features/tickets/data/ticket_repository.dart';
import '../../features/tickets/models/ticket_models.dart';
import '../../features/tickets/presentation/tickets_controller.dart';
import '../../features/users/data/user_management_repository.dart';
import '../../features/users/presentation/users_controller.dart';
import '../models/admin_announcement.dart';
import '../models/app_server_defaults.dart';
import '../models/app_user.dart';
import '../models/managed_user.dart';
import '../models/remote_document.dart';
import '../services/app_settings_repository.dart';
import '../services/desktop_file_save_service.dart';
import '../services/desktop_print_service.dart';
import '../services/desktop_update_agent.dart'
    if (dart.library.html) '../services/desktop_update_agent_web.dart';
import '../services/desktop_update_state_store.dart'
    if (dart.library.html) '../services/desktop_update_state_store_web.dart';
import '../services/lan_file_transfer_service.dart';
import '../services/local_media_storage_service.dart';
import '../services/local_notification_service.dart';
import '../services/print_job_processor.dart';
import '../services/print_job_tracker.dart';
import '../services/web_platform_bridge.dart' as web_bridge;

DateTime? _lastChatSocketErrorLogAt;
String? _lastChatSocketErrorText;

bool _shouldLogChatSocketError(Object error) {
  final now = DateTime.now();
  final text = error.toString();
  final shouldLog =
      _lastChatSocketErrorText != text ||
      _lastChatSocketErrorLogAt == null ||
      now.difference(_lastChatSocketErrorLogAt!) > const Duration(seconds: 30);
  if (shouldLog) {
    _lastChatSocketErrorText = text;
    _lastChatSocketErrorLogAt = now;
  }
  return shouldLog;
}

class ServerConnectionState {
  const ServerConnectionState({
    required this.isConnected,
    required this.message,
    required this.baseUrl,
  });

  final bool isConnected;
  final String message;
  final String baseUrl;
}

class ServerConnectionController extends AsyncNotifier<ServerConnectionState> {
  @override
  Future<ServerConnectionState> build() async {
    final baseUrl =
        ref.watch(apiBaseUrlControllerProvider).valueOrNull ??
        AppConfig.defaultApiBaseUrl;
    return _check(baseUrl);
  }

  Future<ServerConnectionState> refresh({
    String? baseUrl,
    bool preserveConnectedStateOnFailure = false,
  }) async {
    final resolvedBaseUrl =
        baseUrl ??
        ref.read(apiBaseUrlControllerProvider).valueOrNull ??
        AppConfig.defaultApiBaseUrl;
    var result = await _check(resolvedBaseUrl);
    for (var attempt = 0; attempt < 2 && !result.isConnected; attempt++) {
      await Future<void>.delayed(Duration(seconds: attempt + 1));
      result = await _check(resolvedBaseUrl);
    }
    final previous = state.valueOrNull;
    if (!preserveConnectedStateOnFailure ||
        result.isConnected ||
        previous == null ||
        !previous.isConnected ||
        previous.baseUrl != result.baseUrl) {
      state = AsyncData(result);
    }
    return result;
  }

  Future<ServerConnectionState> probe(String baseUrl) => _check(baseUrl);

  Future<ServerConnectionState>? _checkFuture;
  String? _checkFutureBaseUrl;

  Future<ServerConnectionState> _check(String baseUrl) async {
    final normalizedBaseUrl =
        ApiBaseUrlStore.normalize(baseUrl) ?? AppConfig.defaultApiBaseUrl;
    if (_checkFuture != null && _checkFutureBaseUrl == normalizedBaseUrl) {
      return _checkFuture!;
    }

    _checkFutureBaseUrl = normalizedBaseUrl;
    _checkFuture = () async {
      final client = ApiClient(baseUrl: normalizedBaseUrl);
      try {
        final response = await client.dio.get<void>(
          '/health',
          options: Options(
            validateStatus: (code) => code != null && code < 500,
            extra: {'requestSource': 'connectionCheck.startup'},
          ),
        );
        final code = response.statusCode ?? 0;
        final connected =
            code == 200 || code == 401 || code == 403 || code == 404;
        return ServerConnectionState(
          isConnected: connected,
          message: connected
              ? 'الخادم متصل'
              : 'الخادم لا يستجيب بشكل صحيح (${response.statusCode ?? 'بدون كود'})',
          baseUrl: normalizedBaseUrl,
        );
      } catch (error) {
        return ServerConnectionState(
          isConnected: false,
          message: client.mapError(error).message,
          baseUrl: normalizedBaseUrl,
        );
      } finally {
        _checkFuture = null;
        _checkFutureBaseUrl = null;
      }
    }();
    return _checkFuture!;
  }
}

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    return ref.read(themeModeStoreProvider).load();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(themeModeStoreProvider).save(mode);
    state = AsyncData(mode);
  }

  Future<void> cycleThemeMode() async {
    final current = state.valueOrNull ?? ThemeMode.light;
    final next = switch (current) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.system => ThemeMode.light,
    };
    await setThemeMode(next);
  }
}

class ApiBaseUrlController extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final value = await ref.read(apiBaseUrlStoreProvider).load();
    setMediaBaseUrl(value);
    return value;
  }

  Future<void> save(String value) async {
    final normalized =
        ApiBaseUrlStore.normalize(value) ?? AppConfig.defaultApiBaseUrl;
    await ref.read(apiBaseUrlStoreProvider).save(value);
    setMediaBaseUrl(normalized);
    state = AsyncData(normalized);
  }

  Future<void> applyAdminDefault(String value) async {
    final store = ref.read(apiBaseUrlStoreProvider);
    await store.saveAdminDefault(value);
    final isOverride = await store.isUserOverrideEnabled();
    if (isOverride) {
      return;
    }
    final normalized =
        ApiBaseUrlStore.normalize(value) ?? AppConfig.defaultApiBaseUrl;
    setMediaBaseUrl(normalized);
    state = AsyncData(normalized);
  }

  Future<void> reset() async {
    await ref.read(apiBaseUrlStoreProvider).clear();
    setMediaBaseUrl(AppConfig.defaultApiBaseUrl);
    state = const AsyncData(AppConfig.defaultApiBaseUrl);
  }
}

class UserPreferencesController extends AsyncNotifier<UserPreferences> {
  @override
  Future<UserPreferences> build() async {
    return ref.read(userPreferencesStoreProvider).load();
  }

  Future<void> savePreferences(UserPreferences value) async {
    await ref.read(userPreferencesStoreProvider).save(value);
    state = AsyncData(value);
  }

  Future<void> setEnterSendsMessage(bool value) async {
    final current = state.valueOrNull ?? UserPreferences.defaults();
    await savePreferences(current.copyWith(enterSendsMessage: value));
  }

  Future<void> setAutoSaveAfterScan(bool value) async {
    final current = state.valueOrNull ?? UserPreferences.defaults();
    await savePreferences(current.copyWith(autoSaveAfterScan: value));
  }

  Future<void> setScanSaveDirectoryPath(String? path) async {
    final current = state.valueOrNull ?? UserPreferences.defaults();
    await savePreferences(
      path == null || path.trim().isEmpty
          ? current.copyWith(clearScanSaveDirectoryPath: true)
          : current.copyWith(scanSaveDirectoryPath: path.trim()),
    );
  }

  Future<void> setLocalStorageDirectoryPath(String? path) async {
    final current = state.valueOrNull ?? UserPreferences.defaults();
    final normalizedPath = path?.trim();
    final preferredPath = normalizedPath == null || normalizedPath.isEmpty
        ? null
        : normalizedPath;
    if (kIsWeb && web_bridge.isElectron()) {
      await web_bridge.initializeElectronStorage(
        preferredDirectoryPath: preferredPath,
      );
    } else {
      await ref
          .read(localMediaStorageServiceProvider)
          .initializeStorageTree(preferredPath: preferredPath);
    }
    await savePreferences(
      normalizedPath == null || normalizedPath.isEmpty
          ? current.copyWith(clearLocalStorageDirectoryPath: true)
          : current.copyWith(localStorageDirectoryPath: normalizedPath),
    );
    ref.invalidate(chatRepositoryProvider);
    ref.invalidate(documentRepositoryProvider);
  }

  Future<void> setPreferredPrinterName(String? printerName) async {
    final current = state.valueOrNull ?? UserPreferences.defaults();
    await savePreferences(
      printerName == null || printerName.trim().isEmpty
          ? current.copyWith(clearPreferredPrinterName: true)
          : current.copyWith(preferredPrinterName: printerName.trim()),
    );
  }

  Future<void> setNotificationTone(String value) async {
    final current = state.valueOrNull ?? UserPreferences.defaults();
    await savePreferences(current.copyWith(notificationToneId: value));
  }
}

final apiBaseUrlStoreProvider = Provider<ApiBaseUrlStore>(
  (ref) => ApiBaseUrlStore(),
);

final themeModeStoreProvider = Provider<ThemeModeStore>(
  (ref) => ThemeModeStore(),
);
final userPreferencesStoreProvider = Provider<UserPreferencesStore>(
  (ref) => UserPreferencesStore(),
);
final localMediaStorageServiceProvider = Provider<LocalMediaStorageService>(
  (ref) => const LocalMediaStorageService(),
);

final apiBaseUrlControllerProvider =
    AsyncNotifierProvider<ApiBaseUrlController, String>(
      ApiBaseUrlController.new,
    );
final serverConnectionControllerProvider =
    AsyncNotifierProvider<ServerConnectionController, ServerConnectionState>(
      ServerConnectionController.new,
    );
final serverRecoveryRevisionProvider = StateProvider<int>((ref) => 0);

final themeModeControllerProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(
      ThemeModeController.new,
    );
final userPreferencesControllerProvider =
    AsyncNotifierProvider<UserPreferencesController, UserPreferences>(
      UserPreferencesController.new,
    );

final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl =
      ref.watch(apiBaseUrlControllerProvider).valueOrNull ??
      AppConfig.defaultApiBaseUrl;
  return ApiClient(baseUrl: baseUrl);
});

final authRefreshServiceProvider = Provider<AuthRefreshService>((ref) {
  final baseUrl =
      ref.watch(apiBaseUrlControllerProvider).valueOrNull ??
      AppConfig.defaultApiBaseUrl;
  return AuthRefreshService(baseUrl: baseUrl);
});

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// Bumped when tokens are saved/cleared (silent refresh, login, logout) so
/// [authTokenProvider] and the chat socket use the current JWT.
final authCredentialsRevisionProvider = StateProvider<int>((ref) => 0);

/// Bumped when the session is force-cleared so [authControllerProvider]
/// rebuilds and routes to login.
final sessionInvalidationRevisionProvider = StateProvider<int>((ref) => 0);

final authSessionManagerProvider = Provider<AuthSessionManager>((ref) {
  final refreshService = ref.watch(authRefreshServiceProvider);
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
  });

  void defer(VoidCallback callback) {
    Future<void>.microtask(() {
      if (disposed) {
        return;
      }
      callback();
    });
  }

  return AuthSessionManager(
    tokenStorage: ref.read(sessionStoreProvider),
    refreshService: refreshService,
    onSessionCredentialsChanged: () {
      defer(() {
        ref.read(authCredentialsRevisionProvider.notifier).state++;
      });
    },
    onSessionCleared: () {
      defer(() {
        ref.read(authCredentialsRevisionProvider.notifier).state++;
        ref.read(activeConversationIdProvider.notifier).state = null;
        ref.read(sessionInvalidationRevisionProvider.notifier).state++;
        
        ref.invalidate(chatOverviewControllerProvider);
        ref.invalidate(chatRealtimeControllerProvider);
        ref.invalidate(usersControllerProvider);
        ref.invalidate(documentsControllerProvider);
        ref.invalidate(adminDocumentsControllerProvider);
        ref.invalidate(announcementsControllerProvider);
        ref.invalidate(adminAnnouncementsControllerProvider);
        ref.invalidate(ticketsControllerProvider);
        ref.invalidate(closedTicketsControllerProvider);
        ref.invalidate(printerControllerProvider);
      });
    },
  );
});

final authenticatedApiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl =
      ref.watch(apiBaseUrlControllerProvider).valueOrNull ??
      AppConfig.defaultApiBaseUrl;
  return ApiClient(
    baseUrl: baseUrl,
    sessionManager: ref.watch(authSessionManagerProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.read(sessionStoreProvider),
    sessionManager: ref.watch(authSessionManagerProvider),
  );
});

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  return AnnouncementRepository(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(authRepositoryProvider),
  );
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(authRepositoryProvider),
    ref.watch(localMediaStorageServiceProvider),
    ref.watch(userPreferencesControllerProvider).valueOrNull ??
        UserPreferences.defaults(),
  );
});

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  return TicketRepository(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(authRepositoryProvider),
  );
});

final printerRepositoryProvider = Provider<PrinterRepository>((ref) {
  return PrinterRepository(ref.watch(authenticatedApiClientProvider));
});

final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  return BackupRepository(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(authRepositoryProvider),
  );
});

final updateManagementRepositoryProvider = Provider<UpdateManagementRepository>(
  (ref) {
    return UpdateManagementRepository(
      ref.watch(authenticatedApiClientProvider),
      ref.watch(authRepositoryProvider),
    );
  },
);

final chatSocketServiceProvider = Provider<ChatSocketService>((ref) {
  final service = ChatSocketService();
  ref.onDispose(service.dispose);
  return service;
});

final printJobTrackerProvider = Provider<PrintJobTracker>((ref) {
  return PrintJobTracker(SharedPreferencesPrintJobStore());
});

final printJobProcessorProvider = Provider<PrintJobProcessor>((ref) {
  return PrintJobProcessor(
    tracker: ref.watch(printJobTrackerProvider),
    executor: ref.watch(desktopPrintServiceProvider),
    statusEmitter: ref.watch(chatSocketServiceProvider),
    logger: ConsolePrintLogger(),
  );
});

final desktopPrintServiceProvider = Provider<DesktopPrintService>((ref) {
  return DesktopPrintService(
    apiClient: ref.watch(authenticatedApiClientProvider),
    authRepository: ref.watch(authRepositoryProvider),
  );
});

final desktopFileSaveServiceProvider = Provider<DesktopFileSaveService>((ref) {
  return DesktopFileSaveService(
    apiClient: ref.watch(authenticatedApiClientProvider),
    authRepository: ref.watch(authRepositoryProvider),
  );
});

final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) => LocalNotificationService(appName: 'iSmart Messenger'),
);

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return AppSettingsRepository(apiClient: ref.watch(apiClientProvider));
});

final appSettingsServiceProvider = Provider<AppSettingsRepository>((ref) {
  return ref.watch(appSettingsRepositoryProvider);
});

final publicAppSettingsServiceProvider = Provider<AppSettingsRepository>((ref) {
  return ref.watch(appSettingsRepositoryProvider);
});

final appSettingsRevisionProvider = StateProvider<int>((ref) => 0);

final appServerDefaultsProvider = FutureProvider<AppServerDefaults>((ref) {
  ref.watch(appSettingsRevisionProvider);
  final service = ref.read(publicAppSettingsServiceProvider);
  return service.fetchDefaults();
});

final cachedAppServerDefaultsProvider = FutureProvider<AppServerDefaults>((
  ref,
) async {
  return await ref
          .read(publicAppSettingsServiceProvider)
          .loadCachedDefaults() ??
      AppServerDefaults.fallback;
});

final appSettingsSocketSyncProvider = Provider<void>((ref) {
  final subscription = ref.read(chatSocketServiceProvider).events.listen((
    event,
  ) {
    if (event.type == 'app_settings_updated' ||
        event.type == 'socket_connected') {
      ref.read(appSettingsRevisionProvider.notifier).state++;
    }
  });
  ref.onDispose(subscription.cancel);
});

final lanFileTransferServiceProvider = Provider<LanFileTransferService>((ref) {
  final service = LanFileTransferService();
  ref.onDispose(() {
    unawaited(service.stop());
  });
  return service;
});

final desktopUpdateAgentProvider = Provider<DesktopUpdateAgent>((ref) {
  final agent = DesktopUpdateAgent(
    ref.watch(updateManagementRepositoryProvider),
    DesktopUpdateStateStore(),
  );
  ref.onDispose(agent.dispose);
  return agent;
});

final chatAppVisibilityProvider = StateProvider<bool>((ref) => true);

final chatSectionVisibleProvider = StateProvider<bool>((ref) => true);

final activeConversationIdProvider = StateProvider<String?>((ref) => null);

final chatSocketConnectionProvider = FutureProvider<void>((ref) async {
  ref.watch(appSettingsSocketSyncProvider);
  final authState = ref.watch(authControllerProvider);
  ref.watch(serverRecoveryRevisionProvider);
  final authUser = authState.user;
  final socketService = ref.read(chatSocketServiceProvider);

  if (authState.status == AuthStatus.initializing) {
    return;
  }

  final token = await ref.watch(authTokenProvider.future);
  if (authUser == null || token == null || token.isEmpty) {
    socketService.disconnect();
    return;
  }

  final baseUrl =
      ref.watch(apiBaseUrlControllerProvider).valueOrNull ??
      AppConfig.defaultApiBaseUrl;

  try {
    await socketService.connect(
      baseUrl: baseUrl,
      token: token,
      clientType: kIsWeb
          ? (web_bridge.isElectron() ? 'desktop' : 'web')
          : 'desktop',
    );
  } catch (error, stackTrace) {
    // Socket failure should not force logout immediately.
    // REST APIs can still work and token refresh may recover connectivity.
    if (_shouldLogChatSocketError(error)) {
      debugPrint('Chat socket connect failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(authRepositoryProvider),
    ref.watch(localMediaStorageServiceProvider),
    ref.watch(userPreferencesControllerProvider).valueOrNull ??
        UserPreferences.defaults(),
  );
});

final userManagementRepositoryProvider = Provider<UserManagementRepository>((
  ref,
) {
  return UserManagementRepository(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(authRepositoryProvider),
  );
});

enum BootstrapStatus { loading, ready, failed }

final appBootstrapProvider = FutureProvider<BootstrapStatus>((ref) async {
  try {
    await Future.wait([
      ref.read(apiBaseUrlControllerProvider.future),
      ref.read(themeModeControllerProvider.future),
      ref.read(userPreferencesControllerProvider.future),
    ]);
    final preferences =
        ref.read(userPreferencesControllerProvider).valueOrNull ??
        UserPreferences.defaults();
    if (kIsWeb && web_bridge.isElectron()) {
      await web_bridge.initializeElectronStorage(
        preferredDirectoryPath: preferences.localStorageDirectoryPath,
      );
    } else {
      await ref
          .read(localMediaStorageServiceProvider)
          .initializeStorageTree(
            preferredPath: preferences.localStorageDirectoryPath,
          );
    }
    try {
      final defaults = await ref
          .read(publicAppSettingsServiceProvider)
          .fetchDefaults();
      final desktopBaseUrl = defaults.desktopBaseUrl?.trim();
      if (desktopBaseUrl != null && desktopBaseUrl.isNotEmpty) {
        await ref
            .read(apiBaseUrlControllerProvider.notifier)
            .applyAdminDefault(desktopBaseUrl);
      }
    } catch (_) {}

    await ref.read(authControllerProvider.notifier).initializeAuth();

    return BootstrapStatus.ready;
  } catch (_) {
    return BootstrapStatus.failed;
  }
});

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authControllerProvider.select((s) => s.user));
});

final authTokenProvider = FutureProvider<String?>((ref) async {
  ref.watch(authCredentialsRevisionProvider);
  return ref.read(authRepositoryProvider).getValidToken();
});

final itAssetsRepositoryProvider = Provider<ItAssetsRepository>((ref) {
  return ItAssetsRepository(ref.watch(authenticatedApiClientProvider));
});

final chatOverviewControllerProvider =
    AsyncNotifierProvider<ChatOverviewController, ChatOverviewData>(
      ChatOverviewController.new,
    );

final conversationMessagesControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ConversationMessagesController, ConversationMessagesState, String>(
      ConversationMessagesController.new,
    );

final chatRealtimeControllerProvider =
    NotifierProvider<ChatRealtimeController, ChatRealtimeState>(
      ChatRealtimeController.new,
    );

final ticketsControllerProvider =
    AsyncNotifierProvider<TicketsController, TicketOverviewData>(
      TicketsController.new,
    );

final closedTicketsControllerProvider =
    AsyncNotifierProvider<ClosedTicketsController, TicketOverviewData>(
      ClosedTicketsController.new,
    );

final printerControllerProvider =
    AsyncNotifierProvider<PrinterController, PrinterOverviewData>(
      PrinterController.new,
    );

final ticketDetailsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<TicketDetailsController, TicketDetailsData, String>(
      TicketDetailsController.new,
    );

final documentsControllerProvider =
    AsyncNotifierProvider<DocumentsController, List<RemoteDocument>>(
      DocumentsController.new,
    );

final adminDocumentsControllerProvider =
    AsyncNotifierProvider<AdminDocumentsController, List<RemoteDocument>>(
      AdminDocumentsController.new,
    );

final usersControllerProvider =
    AsyncNotifierProvider<UsersController, List<ManagedUser>>(
      UsersController.new,
    );

final announcementsControllerProvider =
    AsyncNotifierProvider<AnnouncementsController, List<AdminAnnouncement>>(
      AnnouncementsController.new,
    );

final adminAnnouncementsControllerProvider =
    AsyncNotifierProvider<
      AdminAnnouncementsController,
      List<AdminAnnouncement>
    >(AdminAnnouncementsController.new);
