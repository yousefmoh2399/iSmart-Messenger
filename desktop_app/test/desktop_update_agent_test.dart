import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_app/features/admin/data/update_management_repository.dart';
import 'package:desktop_app/features/admin/models/update_management_models.dart';
import 'package:desktop_app/features/auth/data/auth_repository.dart';
import 'package:desktop_app/core/network/api_client.dart';
import 'package:desktop_app/shared/models/app_user.dart';
import 'package:desktop_app/shared/services/desktop_update_agent.dart';
import 'package:desktop_app/shared/services/desktop_update_state.dart';
import 'package:desktop_app/shared/services/desktop_update_state_store.dart';

class FakeUpdateManagementRepository implements UpdateManagementRepository {
  int heartbeatCalls = 0;
  bool shouldThrow = false;
  Completer<DeviceHeartbeatResponse>? inFlightHeartbeat;
  String? lastDeviceUid;
  String? lastBranchCode;

  @override
  String get baseUrl => 'http://192.168.1.50:5000';

  @override
  Future<String?> getAccessToken() async => 'test-token';

  @override
  Future<DeviceHeartbeatResponse> heartbeatDevice({
    required String deviceUid,
    required String deviceName,
    required String hostName,
    String? localIp,
    required String branchCode,
    required String channel,
    required String appVersion,
    required String osName,
    required String osVersion,
    required String architecture,
    required String connectionStatus,
    required bool autoUpdateEnabled,
    required bool silentInstallEnabled,
    String platform = 'desktop_windows',
  }) async {
    heartbeatCalls++;
    lastDeviceUid = deviceUid;
    lastBranchCode = branchCode;

    if (shouldThrow) {
      throw Exception('Server unreachable');
    }

    if (inFlightHeartbeat != null) {
      return inFlightHeartbeat!.future;
    }

    return const DeviceHeartbeatResponse(
      pendingTasks: [],
      heartbeatIntervalSeconds: 30,
      latestRelease: ManagedUpdateRelease(
        id: 'rel-1',
        version: '1.2.0',
        buildNumber: '2',
        channel: 'stable',
        platform: 'desktop_windows',
        notes: 'Notes',
        mandatory: false,
        isEnabled: true,
        installerKind: 'exe',
        packageType: 'full',
        packageLayout: 'bundle_zip',
        entryExecutable: 'app.exe',
        minSupportedVersion: null,
        targetArchitecture: 'x64',
        minWindowsBuild: null,
        rolloutPercentage: 100,
        silentInstallArgs: '/S',
        checksumSha256: null,
        fileName: 'installer.exe',
        fileSize: 1024,
        downloadPath: '/api/updates/releases/rel-1/download',
        downloadUrl: 'http://localhost:5000/api/updates/releases/rel-1/download',
        externalDownloadUrl: null,
        createdAt: null,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDesktopUpdateStateStore implements DesktopUpdateStateStore {
  DesktopUpdateState state = DesktopUpdateState.idle();

  @override
  Future<DesktopUpdateState> load() async => state;

  @override
  Future<void> markCompleted(String version) async {
    state = DesktopUpdateState(status: 'completed', targetVersion: version);
  }

  @override
  Future<void> markDownloading({
    required String taskId,
    required String releaseId,
    required String targetVersion,
    required String packageType,
    required String installerKind,
    required String packageLayout,
    required String entryExecutable,
    required String silentInstallArgs,
    required String fileName,
    required String currentVersion,
  }) async {
    state = DesktopUpdateState(status: 'downloading', targetVersion: targetVersion);
  }

  @override
  Future<void> markFailed(String error) async {
    state = DesktopUpdateState(status: 'failed', lastError: error);
  }

  @override
  Future<void> markAwaitingHealthcheck() async {
    state = DesktopUpdateState(status: 'awaiting_healthcheck');
  }

  @override
  Future<void> markInstalling() async {
    state = DesktopUpdateState(status: 'installing');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthRepository implements AuthRepository {
  @override
  Future<String?> getToken() async => 'test-bearer-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DesktopUpdateAgent Robustness Tests', () {
    test('checkNowDetailed succeeds even if user is not attached yet (uses fallback branchCode)', () async {
      final fakeRepo = FakeUpdateManagementRepository();
      final fakeStore = FakeDesktopUpdateStateStore();
      final agent = DesktopUpdateAgent(fakeRepo, fakeStore);

      final response = await agent.checkNowDetailed();

      expect(response, isNotNull);
      expect(response!.latestRelease?.version, '1.2.0');
      expect(fakeRepo.heartbeatCalls, 1);
      expect(fakeRepo.lastDeviceUid, isNotNull);
      expect(fakeRepo.lastBranchCode, 'main');
    });

    test('attachUser attaches user to agent and updates branchCode', () async {
      final fakeRepo = FakeUpdateManagementRepository();
      final fakeStore = FakeDesktopUpdateStateStore();
      final agent = DesktopUpdateAgent(fakeRepo, fakeStore);

      final user = AppUser(
        id: 'u1',
        username: 'user1',
        fullName: 'User One',
        role: 'user',
        departmentId: null,
        branchId: null,
        branchCode: 'alex',
        isOnline: true,
        presenceStatus: 'online',
        isActive: true,
        avatarUrl: null,
        lastSeen: null,
        lastActiveAt: null,
        maxAttachmentSizeMB: 20,
        permissions: const {},
        chatPreferences: ChatPreferences.defaults,
      );
      agent.attachUser(user);

      expect(agent.currentUser, equals(user));

      await agent.checkNowDetailed();
      expect(fakeRepo.lastBranchCode, 'alex');
    });

    test('Concurrent checkNowDetailed calls share the single in-flight heartbeat future', () async {
      final fakeRepo = FakeUpdateManagementRepository();
      final fakeStore = FakeDesktopUpdateStateStore();
      final agent = DesktopUpdateAgent(fakeRepo, fakeStore);

      final completer = Completer<DeviceHeartbeatResponse>();
      fakeRepo.inFlightHeartbeat = completer;

      final call1 = agent.checkNowDetailed();
      final call2 = agent.checkNowDetailed();

      completer.complete(const DeviceHeartbeatResponse(
        pendingTasks: [],
        heartbeatIntervalSeconds: 30,
      ));

      final results = await Future.wait([call1, call2]);
      expect(results[0], isNotNull);
      expect(results[1], isNotNull);
      expect(fakeRepo.heartbeatCalls, 1); // Exactly 1 network request!
    });

    test('checkNowDetailed rethrows error so UI can display specific failure reason', () async {
      final fakeRepo = FakeUpdateManagementRepository();
      fakeRepo.shouldThrow = true;
      final fakeStore = FakeDesktopUpdateStateStore();
      final agent = DesktopUpdateAgent(fakeRepo, fakeStore);

      expect(() => agent.checkNowDetailed(), throwsA(isA<Exception>()));
    });
  });

  group('UpdateManagementRepository Download URI Resolution', () {
    test('routes server localhost download URLs through active client baseUrl', () {
      final apiClient = ApiClient(baseUrl: 'http://192.168.1.100:8000');
      final fakeAuthRepo = FakeAuthRepository();
      final repo = UpdateManagementRepository(apiClient, fakeAuthRepo);

      // Server returned downloadUrl pointing to localhost:5000
      final resolved = repo.downloadReleaseArtifact(
        releaseId: 'rel-1',
        fileName: 'installer.exe',
        downloadUrl: 'http://localhost:5000/api/updates/releases/rel-1/download',
        destinationDirectory: 'C:/temp/test',
        maxAttempts: 1,
      );

      // We expect the download to attempt connecting to 192.168.1.100:8000, not localhost:5000
      expect(resolved, throwsA(anything));
    });
  });
}
