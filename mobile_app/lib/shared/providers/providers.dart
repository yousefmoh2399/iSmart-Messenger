import 'package:dio/dio.dart';
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
import '../../features/admin/presentation/announcements_controller.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/data/chat_socket_service.dart';
import '../../features/chat/models/chat_models.dart';
import '../../features/chat/presentation/chat_overview_controller.dart';
import '../../features/chat/presentation/chat_realtime_controller.dart';
import '../../features/files/data/document_repository.dart';
import '../../features/files/presentation/pending_uploads_controller.dart';
import '../../features/files/presentation/remote_documents_controller.dart';
import '../../features/it_assets/data/mobile_it_assets_repository.dart';
import '../../features/printers/data/printer_repository.dart';
import '../../features/printers/models/printer_models.dart';
import '../../features/printers/presentation/printer_controller.dart';
import '../../features/scanner/data/image_processing_service.dart';
import '../../features/scanner/data/local_document_store.dart';
import '../../features/scanner/data/pdf_builder_service.dart';
import '../../features/scanner/data/scanner_service.dart';
import '../../features/scanner/data/signature_composer_service.dart';
import '../../features/scanner/data/signature_storage_service.dart';
import '../../features/scanner/presentation/scan_session_controller.dart';
import '../../features/tickets/data/ticket_repository.dart';
import '../../features/tickets/models/ticket_models.dart';
import '../../features/tickets/presentation/tickets_controller.dart';
import '../../features/users/data/user_management_repository.dart';
import '../../features/users/presentation/users_controller.dart';
import '../models/admin_announcement.dart';
import '../models/app_user.dart';
import '../models/managed_user.dart';
import '../models/pending_upload.dart';
import '../models/remote_document.dart';
import '../models/scan_session.dart';
import '../services/app_settings_repository.dart';
import '../services/local_media_storage_service.dart';
import '../services/local_notification_service.dart';
import '../services/push_notification_service.dart';
import '../services/remote_desktop_file_service.dart';
import '../services/remote_print_service.dart';
import '../services/update_check_service.dart';

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

  Future<ServerConnectionState> _check(String baseUrl) async {
    final normalizedBaseUrl =
        ApiBaseUrlStore.normalize(baseUrl) ?? AppConfig.defaultApiBaseUrl;
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
    }
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
    await ref
        .read(localMediaStorageServiceProvider)
        .initializeStorageTree(
          preferredPath: normalizedPath == null || normalizedPath.isEmpty
              ? null
              : normalizedPath,
        );
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

final authenticatedApiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl =
      ref.watch(apiBaseUrlControllerProvider).valueOrNull ??
      AppConfig.defaultApiBaseUrl;
  final authRepository = ref.read(authRepositoryProvider);
  return ApiClient(baseUrl: baseUrl, authRepository: authRepository);
});

final localDocumentStoreProvider = Provider<LocalDocumentStore>(
  (ref) => LocalDocumentStore(),
);

final imageProcessingServiceProvider = Provider<ImageProcessingService>(
  (ref) => ImageProcessingService(),
);

final pdfBuilderServiceProvider = Provider<PdfBuilderService>(
  (ref) => PdfBuilderService(),
);

final scannerServiceProvider = Provider<ScannerService>(
  (ref) => ScannerService(),
);

final signatureStorageServiceProvider = Provider<SignatureStorageService>(
  (ref) => SignatureStorageService(),
);

final signatureComposerServiceProvider = Provider<SignatureComposerService>(
  (ref) => SignatureComposerService(),
);

/// Bumped whenever tokens are saved or cleared (including silent refresh) so
/// [authTokenProvider] refetches and socket/widgets see the current access token.
final authCredentialsRevisionProvider = StateProvider<int>((ref) => 0);

/// Bumped when the session is force-cleared so [authControllerProvider]
/// rebuilds and routes to login.
final sessionInvalidationRevisionProvider = StateProvider<int>((ref) => 0);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    onSessionCredentialsChanged: () {
      ref.read(authCredentialsRevisionProvider.notifier).state++;
    },
    onSessionCleared: () {
      ref.read(authCredentialsRevisionProvider.notifier).state++;
      ref.read(activeConversationIdProvider.notifier).state = null;
      ref.read(sessionInvalidationRevisionProvider.notifier).state++;
      
      if (ref.exists(chatOverviewControllerProvider)) ref.read(chatOverviewControllerProvider.notifier).resetState();
      if (ref.exists(usersControllerProvider)) ref.read(usersControllerProvider.notifier).resetState();
      if (ref.exists(remoteDocumentsControllerProvider)) ref.read(remoteDocumentsControllerProvider.notifier).resetState();
      if (ref.exists(adminDocumentsControllerProvider)) ref.read(adminDocumentsControllerProvider.notifier).resetState();
      if (ref.exists(announcementsControllerProvider)) ref.read(announcementsControllerProvider.notifier).resetState();
      if (ref.exists(adminAnnouncementsControllerProvider)) ref.read(adminAnnouncementsControllerProvider.notifier).resetState();
      if (ref.exists(ticketsControllerProvider)) ref.read(ticketsControllerProvider.notifier).resetState();
      if (ref.exists(mobilePrinterControllerProvider)) ref.read(mobilePrinterControllerProvider.notifier).resetState();
      if (ref.exists(pendingUploadsControllerProvider)) ref.read(pendingUploadsControllerProvider.notifier).resetState();
      if (ref.exists(scanSessionControllerProvider)) ref.read(scanSessionControllerProvider.notifier).resetState();

      ref.invalidate(chatOverviewControllerProvider);
      ref.invalidate(chatRealtimeControllerProvider);
      ref.invalidate(usersControllerProvider);
      ref.invalidate(remoteDocumentsControllerProvider);
      ref.invalidate(adminDocumentsControllerProvider);
      ref.invalidate(announcementsControllerProvider);
      ref.invalidate(adminAnnouncementsControllerProvider);
      ref.invalidate(ticketsControllerProvider);
      ref.invalidate(mobilePrinterControllerProvider);
      ref.invalidate(pendingUploadsControllerProvider);
      ref.invalidate(scanSessionControllerProvider);
    },
  );
});

final announcementRepositoryProvider = Provider<AnnouncementRepository>((ref) {
  return AnnouncementRepository(ref.watch(authenticatedApiClientProvider));
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(localMediaStorageServiceProvider),
    ref.watch(userPreferencesControllerProvider).valueOrNull ??
        UserPreferences.defaults(),
    authRepository: ref.watch(authRepositoryProvider),
  );
});

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  return TicketRepository(ref.watch(authenticatedApiClientProvider));
});

final mobilePrinterRepositoryProvider = Provider<MobilePrinterRepository>((
  ref,
) {
  return MobilePrinterRepository(ref.watch(authenticatedApiClientProvider));
});

final mobileItAssetsRepositoryProvider = Provider<MobileItAssetsRepository>((
  ref,
) {
  return MobileItAssetsRepository(ref.watch(authenticatedApiClientProvider));
});

final chatSocketServiceProvider = Provider<ChatSocketService>((ref) {
  final service = ChatSocketService();
  ref.onDispose(service.dispose);
  return service;
});

final remotePrintServiceProvider = Provider<RemotePrintService>((ref) {
  return RemotePrintService(
    ref.watch(chatSocketServiceProvider),
    ref.watch(authRepositoryProvider),
  );
});

final remoteDesktopFileServiceProvider = Provider<RemoteDesktopFileService>((
  ref,
) {
  return RemoteDesktopFileService(
    ref.watch(chatSocketServiceProvider),
    ref.watch(authenticatedApiClientProvider),
  );
});

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return AppSettingsRepository(apiClient: ref.read(apiClientProvider));
});

final appSettingsServiceProvider = Provider<AppSettingsRepository>((ref) {
  return ref.watch(appSettingsRepositoryProvider);
});

final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) => LocalNotificationService(appName: 'الشات الداخلي'),
);

final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final service = PushNotificationService(
    ref.watch(authenticatedApiClientProvider),
    ref.watch(authRepositoryProvider),
    ref.watch(localNotificationServiceProvider),
  );
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

final chatAppVisibilityProvider = StateProvider<bool>((ref) => true);

final activeConversationIdProvider = StateProvider<String?>((ref) => null);

final chatSocketConnectionProvider = FutureProvider<void>((ref) async {
  final authState = ref.watch(authControllerProvider);
  ref.watch(serverRecoveryRevisionProvider);
  final authUser = authState.valueOrNull;
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
      clientType: 'mobile',
    );
  } catch (error, stackTrace) {
    // Do not leave [chatSocketConnectionProvider] in AsyncError — dependents
    // (e.g. chat overview) would stay broken until restart.
    if (_shouldLogChatSocketError(error)) {
      debugPrint('Chat socket connect failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository(
    apiClient: ref.watch(authenticatedApiClientProvider),
    localStorage: ref.watch(localMediaStorageServiceProvider),
    preferences:
        ref.watch(userPreferencesControllerProvider).valueOrNull ??
        UserPreferences.defaults(),
  );
});

final userManagementRepositoryProvider = Provider<UserManagementRepository>((
  ref,
) {
  return UserManagementRepository(ref.watch(authenticatedApiClientProvider));
});

enum BootstrapStatus { loading, ready, failed }

final appBootstrapProvider = FutureProvider<BootstrapStatus>((ref) async {
  try {
    await Future.wait([
      ref.read(localDocumentStoreProvider).initialize(),
      ref.read(apiBaseUrlControllerProvider.future),
      ref.read(themeModeControllerProvider.future),
      ref.read(userPreferencesControllerProvider.future),
    ]);
    final preferences =
        ref.read(userPreferencesControllerProvider).valueOrNull ??
        UserPreferences.defaults();
    await ref
        .read(localMediaStorageServiceProvider)
        .initializeStorageTree(
          preferredPath: preferences.localStorageDirectoryPath,
        );

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

final currentChatPreferencesProvider = Provider<ChatPreferences>((ref) {
  return ref.watch(currentUserProvider)?.chatPreferences ??
      ChatPreferences.defaults;
});

final chatOverviewControllerProvider =
    AsyncNotifierProvider<ChatOverviewController, ChatOverviewData>(
      ChatOverviewController.new,
    );

/// Must track [authControllerProvider], not only [authRepositoryProvider], so the
/// token is re-read after login/logout (Riverpod would otherwise cache the first
/// [getToken()] result forever while the repository instance stays the same).
/// Also watches [authCredentialsRevisionProvider] so silent token rotation updates
/// consumers (socket reconnect, attachment Authorization headers).
final authTokenProvider = FutureProvider<String?>((ref) async {
  ref.watch(authControllerProvider);
  ref.watch(authCredentialsRevisionProvider);
  return ref.read(authRepositoryProvider).getValidToken();
});
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
final mobilePrinterControllerProvider =
    AsyncNotifierProvider<MobilePrinterController, MobilePrinterOverview>(
      MobilePrinterController.new,
    );
final ticketDetailsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<TicketDetailsController, TicketDetailsData, String>(
      TicketDetailsController.new,
    );

final remoteDocumentsControllerProvider =
    AsyncNotifierProvider<RemoteDocumentsController, List<RemoteDocument>>(
      RemoteDocumentsController.new,
    );

final adminDocumentsControllerProvider =
    AsyncNotifierProvider<AdminDocumentsController, List<RemoteDocument>>(
      AdminDocumentsController.new,
    );

final pendingUploadsControllerProvider =
    AsyncNotifierProvider<PendingUploadsController, List<PendingUpload>>(
      PendingUploadsController.new,
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
    AsyncNotifierProvider<AdminAnnouncementsController,
        List<AdminAnnouncement>>(AdminAnnouncementsController.new);

final scanSessionControllerProvider =
    AsyncNotifierProvider<ScanSessionController, ScanSession?>(
      ScanSessionController.new,
    );

/// Human-readable save-progress message updated by [ScanSessionController]
/// during PDF generation. Empty string when idle.
final scanSaveProgressProvider = StateProvider<String>((ref) => '');

final updateCheckServiceProvider = Provider<UpdateCheckService>((ref) {
  return UpdateCheckService(ref.watch(authenticatedApiClientProvider));
});

class SyncBannerState {
  const SyncBannerState({
    required this.isOffline,
    required this.isSyncing,
    required this.message,
  });

  final bool isOffline;
  final bool isSyncing;
  final String message;

  factory SyncBannerState.hidden() =>
      const SyncBannerState(isOffline: false, isSyncing: false, message: '');
}

final syncBannerStateProvider = StateProvider<SyncBannerState>(
  (ref) => SyncBannerState.hidden(),
);




