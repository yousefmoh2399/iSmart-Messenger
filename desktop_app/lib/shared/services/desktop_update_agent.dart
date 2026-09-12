import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:desktop_app/shared/services/desktop_update_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/admin/data/update_management_repository.dart';
import '../../features/admin/models/update_management_models.dart';
import '../../shared/models/app_user.dart';
import 'desktop_update_paths.dart';
import 'desktop_update_state_store.dart';
import 'web_platform_bridge.dart' as web_bridge;

class DesktopUpdateEvent {
  const DesktopUpdateEvent({
    required this.type,
    this.taskId,
    this.status,
    this.message = '',
    this.progress,
  });

  final String type;
  final String? taskId;
  final String? status;
  final String message;
  final int? progress;

  factory DesktopUpdateEvent.status({
    required String taskId,
    required String status,
    required String message,
    required int progress,
  }) {
    return DesktopUpdateEvent(
      type: 'status',
      taskId: taskId,
      status: status,
      message: message,
      progress: progress,
    );
  }

  factory DesktopUpdateEvent.completed({
    required String taskId,
    required String message,
  }) {
    return DesktopUpdateEvent(
      type: 'completed',
      taskId: taskId,
      message: message,
      progress: 100,
    );
  }

  factory DesktopUpdateEvent.failed({
    required String taskId,
    required String message,
  }) {
    return DesktopUpdateEvent(
      type: 'failed',
      taskId: taskId,
      message: message,
      progress: 100,
    );
  }

  factory DesktopUpdateEvent.readyToRestart({
    required String taskId,
    required String message,
  }) {
    return DesktopUpdateEvent(
      type: 'ready_to_restart',
      taskId: taskId,
      message: message,
      progress: 100,
    );
  }

  factory DesktopUpdateEvent.heartbeatError(String message) {
    return DesktopUpdateEvent(type: 'heartbeat_error', message: message);
  }
}

class DesktopUpdateAgent {
  DesktopUpdateAgent(this._repository, this._stateStore);

  static const _deviceUidKey = 'desktop_update_device_uid';

  final UpdateManagementRepository _repository;
  final DesktopUpdateStateStore _stateStore;
  final StreamController<DesktopUpdateEvent> _eventsController =
      StreamController<DesktopUpdateEvent>.broadcast();

  bool _disposed = false;
  bool _isHeartbeatRunning = false;
  bool _isTaskRunning = false;
  String _connectionStatus = 'online';
  AppUser? _currentUser;
  String? _deviceUid;
  DeviceHeartbeatResponse? _lastHeartbeatResponse;

  static const int _progressReportStepPercent = 5;
  int _lastProgressReported = -1;
  String? _lastReportedStatus;
  bool _isReportingProgress = false;
  _QueuedTaskReport? _queuedProgressReport;

  Stream<DesktopUpdateEvent> get events => _eventsController.stream;
  DeviceHeartbeatResponse? get lastHeartbeatResponse => _lastHeartbeatResponse;
  String? get deviceUid => _deviceUid;
  AppUser? get currentUser => _currentUser;

  void _addEvent(DesktopUpdateEvent event) {
    if (_disposed || _eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  Future<void> start(AppUser user) async {
    if (_disposed) {
      return;
    }
    _currentUser = user;
    if (kIsWeb) {
      _deviceUid ??= await _loadOrCreateDeviceUid();
      return;
    }
    await DesktopUpdatePaths.ensureInitialized();
    _deviceUid ??= await _loadOrCreateDeviceUid();
    await _reconcilePostRestartState();
    await _emitPreparedUpdateStateIfNeeded();
  }

  Future<void> checkNow() async {
    await _runHeartbeat();
  }

  Future<DeviceHeartbeatResponse?> checkNowDetailed() async {
    return _runHeartbeat();
  }

  void setConnectionStatus(String status) {
    final normalized = switch (status.trim().toLowerCase()) {
      'online' => 'online',
      'idle' => 'idle',
      'meeting' => 'meeting',
      'lunch' => 'lunch',
      'offline' => 'offline',
      _ => 'online',
    };
    _connectionStatus = normalized;
  }

  void stop() {
    _isHeartbeatRunning = false;
    _isTaskRunning = false;
    _currentUser = null;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    stop();
    _eventsController.close();
  }

  Future<DeviceHeartbeatResponse?> _runHeartbeat() async {
    if (_disposed || _isHeartbeatRunning || _currentUser == null) {
      return _lastHeartbeatResponse;
    }
    _isHeartbeatRunning = true;
    try {
      final appVersion = await _resolveAppVersion();
      final electronInfo = kIsWeb && web_bridge.isElectron()
          ? await web_bridge.getElectronDeviceInfo()
          : const <String, dynamic>{};
      final response = await _repository.heartbeatDevice(
        deviceUid: _deviceUid!,
        deviceName: await _resolveDeviceName(),
        hostName: kIsWeb
            ? (electronInfo['hostName']?.toString().trim().isNotEmpty == true
                  ? electronInfo['hostName'].toString().trim()
                  : 'web-browser')
            : _resolveHostName(),
        localIp: kIsWeb
            ? (electronInfo['localIp']?.toString().trim().isNotEmpty == true
                  ? electronInfo['localIp'].toString().trim()
                  : null)
            : await _resolvePrimaryLocalIpv4(),
        branchCode: _resolveBranchCode(_currentUser!),
        channel: 'stable',
        appVersion: appVersion,
        osName: kIsWeb
            ? (electronInfo['osName']?.toString().trim().isNotEmpty == true
                  ? 'electron-${electronInfo['osName'].toString().trim()}'
                  : 'web')
            : Platform.operatingSystem,
        osVersion: kIsWeb
            ? (electronInfo['osVersion']?.toString().trim().isNotEmpty == true
                  ? electronInfo['osVersion'].toString().trim()
                  : 'browser')
            : Platform.operatingSystemVersion,
        architecture: kIsWeb
            ? (electronInfo['architecture']?.toString().trim().isNotEmpty ==
                      true
                  ? electronInfo['architecture'].toString().trim()
                  : 'web')
            : _resolveArchitecture(),
        connectionStatus: _connectionStatus,
        autoUpdateEnabled: !kIsWeb,
        silentInstallEnabled: !kIsWeb,
      );
      _lastHeartbeatResponse = response;
      if (!kIsWeb && response.pendingTasks.isNotEmpty && !_isTaskRunning) {
        await _executePendingTask(response.pendingTasks.first);
      }
      return response;
    } catch (error) {
      _addEvent(DesktopUpdateEvent.heartbeatError(error.toString()));
      return _lastHeartbeatResponse;
    } finally {
      _isHeartbeatRunning = false;
    }
  }

  Future<void> _executePendingTask(PendingUpdateTask task) async {
    if (_isTaskRunning || _currentUser == null) {
      return;
    }
    _isTaskRunning = true;

    _lastProgressReported = -1;
    _lastReportedStatus = null;
    _isReportingProgress = false;
    _queuedProgressReport = null;

    try {
      final currentVersion = await _resolveAppVersion();
      final currentState = await _stateStore.load();
      final hasPreparedArtifact =
          currentState.taskId == task.id &&
          currentState.targetVersion == task.release.version &&
          currentState.status == 'downloaded' &&
          currentState.artifactPath != null &&
          currentState.artifactPath!.trim().isNotEmpty &&
          File(currentState.artifactPath!).existsSync();

      if (_sameVersion(currentVersion, task.release.version)) {
        await _reportTask(
          taskId: task.id,
          status: 'completed',
          progress: 100,
          message: 'The device is already on ${task.release.version}.',
        );
        await _stateStore.markCompleted(currentVersion);
        _addEvent(
          DesktopUpdateEvent.completed(
            taskId: task.id,
            message: 'The update was already applied.',
          ),
        );
        return;
      }

      if (hasPreparedArtifact) {
        _addEvent(
          DesktopUpdateEvent.readyToRestart(
            taskId: task.id,
            message:
                'تم تنزيل التحديث ${task.release.version}. أعد تشغيل التطبيق عندما يناسبك لإكمال التثبيت.',
          ),
        );
        return;
      }

      await _emitAndReport(
        taskId: task.id,
        status: 'acknowledged',
        progress: task.progress == 0 ? 1 : task.progress,
        message: 'Preparing update package.',
      );

      await _stateStore.markDownloading(
        taskId: task.id,
        releaseId: task.release.id,
        targetVersion: task.release.version,
        packageType: task.release.packageType,
        installerKind: task.release.installerKind,
        packageLayout: task.release.packageLayout,
        entryExecutable: task.release.entryExecutable,
        silentInstallArgs: task.release.silentInstallArgs,
        fileName:
            task.release.fileName ?? 'release-${task.release.version}.bin',
        currentVersion: currentVersion,
      );

      await _emitAndReport(
        taskId: task.id,
        status: 'downloading',
        progress: 5,
        message: 'Downloading update package.',
      );

      final artifactPath = await _repository.downloadReleaseArtifact(
        releaseId: task.release.id,
        fileName:
            task.release.fileName ?? 'release-${task.release.version}.bin',
        downloadUrl:
            task.release.downloadUrl ?? task.release.externalDownloadUrl,
        destinationDirectory: DesktopUpdatePaths.downloadsRoot,
        onReceiveProgress: (received, total) {
          final progress = _mapDownloadProgress(received, total);
          _addEvent(
            DesktopUpdateEvent.status(
              taskId: task.id,
              status: 'downloading',
              message: 'Downloading update package.',
              progress: progress,
            ),
          );
          unawaited(
            _reportTask(
              taskId: task.id,
              status: 'downloading',
              progress: progress,
              message: 'Downloading update package.',
            ),
          );
        },
      );

      String digest = '';
      if ((task.release.checksumSha256 ?? '').trim().isNotEmpty) {
        await _emitAndReport(
          taskId: task.id,
          status: 'downloading',
          progress: 55,
          message: 'Verifying package checksum.',
        );
        digest = await _calculateFileSha256(artifactPath);
        final expected = task.release.checksumSha256!.trim().toLowerCase();
        if (digest.toLowerCase() != expected) {
          throw StateError(
            'Checksum mismatch. expected=$expected actual=$digest',
          );
        }
      }
      await _stateStore.markDownloaded(
        artifactPath: artifactPath,
        artifactSha256: digest,
      );

      await _emitAndReport(
        taskId: task.id,
        status: 'downloading',
        progress: 100,
        message:
            'اكتمل تنزيل التحديث. أعد تشغيل التطبيق عندما يناسبك لإكمال التثبيت.',
      );
      _addEvent(
        DesktopUpdateEvent.readyToRestart(
          taskId: task.id,
          message:
              'تم تنزيل التحديث ${task.release.version}. يمكنك متابعة عملك الآن ثم إعادة تشغيل التطبيق لاحقًا.',
        ),
      );
    } catch (error) {
      await _stateStore.markFailed(error.toString());
      await _reportTask(
        taskId: task.id,
        status: 'failed',
        progress: 100,
        message: error.toString(),
      );
      _addEvent(
        DesktopUpdateEvent.failed(taskId: task.id, message: error.toString()),
      );
    } finally {
      _isTaskRunning = false;
    }
  }

  Future<void> _emitAndReport({
    required String taskId,
    required String status,
    required int progress,
    required String message,
  }) async {
    _addEvent(
      DesktopUpdateEvent.status(
        taskId: taskId,
        status: status,
        message: message,
        progress: progress.clamp(0, 100),
      ),
    );
    await _reportTask(
      taskId: taskId,
      status: status,
      progress: progress,
      message: message,
    );
  }

  Future<void> _reportTask({
    required String taskId,
    required String status,
    required int progress,
    required String message,
  }) async {
    if (_deviceUid == null) {
      return;
    }
    final isTerminalStatus = [
      'completed',
      'failed',
      'cancelled',
    ].contains(status);
    final shouldSend =
        isTerminalStatus ||
        status != _lastReportedStatus ||
        status != 'downloading' ||
        progress == 0 ||
        progress == 100 ||
        (progress - _lastProgressReported).abs() >= _progressReportStepPercent;
    if (!shouldSend) {
      return;
    }

    _queuedProgressReport = _QueuedTaskReport(
      taskId: taskId,
      status: status,
      progress: progress.clamp(0, 100),
      message: message,
    );
    if (_isReportingProgress) {
      return;
    }

    while (_queuedProgressReport != null && !_disposed) {
      final report = _queuedProgressReport!;
      _queuedProgressReport = null;
      _isReportingProgress = true;
      try {
        await _repository.reportTaskProgress(
          taskId: report.taskId,
          deviceUid: _deviceUid!,
          status: report.status,
          progress: report.progress,
          message: report.message,
          connectionStatus: _connectionStatus,
        );
        _lastReportedStatus = report.status;
        _lastProgressReported = report.progress;
      } on DioException {
        // Progress reports are telemetry only. They must not fail the updater
        // if the server throttles them or the task was already finalized.
      } finally {
        _isReportingProgress = false;
      }
    }
  }

  Future<void> _reconcilePostRestartState() async {
    final taskState = await _stateStore.load();
    final taskId = taskState.taskId?.trim();
    final targetVersion = taskState.targetVersion?.trim();
    if (taskId == null ||
        taskId.isEmpty ||
        targetVersion == null ||
        targetVersion.isEmpty) {
      return;
    }

    final currentVersion = await _resolveAppVersion();
    if (taskState.status == 'awaiting_healthcheck') {
      if (_sameVersion(currentVersion, targetVersion)) {
        await _reportTask(
          taskId: taskId,
          status: 'completed',
          progress: 100,
          message: 'Update $targetVersion was confirmed after restart.',
        );
        await _stateStore.markCompleted(currentVersion);
        _addEvent(
          DesktopUpdateEvent.completed(
            taskId: taskId,
            message: 'The application restarted on the new version.',
          ),
        );
      } else {
        final message =
            'Updater restarted the app but version $targetVersion was not activated. Current version: $currentVersion.';
        await _reportTask(
          taskId: taskId,
          status: 'failed',
          progress: 100,
          message: message,
        );
        await _stateStore.markRolledBack(message);
      }
      return;
    }

    if (taskState.isTerminal && taskState.lastKnownVersion == currentVersion) {
      return;
    }
  }

  Future<void> _emitPreparedUpdateStateIfNeeded() async {
    final taskState = await _stateStore.load();
    final taskId = taskState.taskId?.trim();
    if (taskId == null || taskId.isEmpty) {
      return;
    }

    if (taskState.status == 'downloaded' &&
        taskState.artifactPath != null &&
        taskState.artifactPath!.trim().isNotEmpty &&
        File(taskState.artifactPath!).existsSync()) {
      _addEvent(
        DesktopUpdateEvent.readyToRestart(
          taskId: taskId,
          message:
              'يوجد تحديث جاهز للتثبيت بالفعل. أعد تشغيل التطبيق عندما يناسبك.',
        ),
      );
    }
  }

  Future<DesktopUpdateState> loadState() => _stateStore.load();

  Future<void> restartToApplyPreparedUpdate() async {
    final state = await _stateStore.load();
    final taskId = state.taskId?.trim();
    final artifactPath = state.artifactPath?.trim();
    if (taskId == null ||
        taskId.isEmpty ||
        artifactPath == null ||
        artifactPath.isEmpty ||
        !File(artifactPath).existsSync()) {
      throw StateError('لا توجد حزمة تحديث جاهزة للتثبيت على هذا الجهاز.');
    }

    final release = _releaseFromState(state);
    if (release == null) {
      throw StateError(
        'بيانات التحديث المحلية غير مكتملة ولا يمكن متابعة التثبيت.',
      );
    }

    await _emitAndReport(
      taskId: taskId,
      status: 'installing',
      progress: 80,
      message: 'يتم الآن إغلاق التطبيق لإكمال تثبيت التحديث.',
    );
    await _stateStore.markInstalling();

    final installResult = await _runInstaller(
      taskId: taskId,
      artifactPath: artifactPath,
      release: release,
    );
    if (!installResult.success) {
      await _stateStore.markFailed(installResult.message);
      await _reportTask(
        taskId: taskId,
        status: 'failed',
        progress: 100,
        message: installResult.message,
      );
      _addEvent(
        DesktopUpdateEvent.failed(
          taskId: taskId,
          message: installResult.message,
        ),
      );
      return;
    }

    if (installResult.completionHandledExternally) {
      await _stateStore.markAwaitingHealthcheck();
      await _emitAndReport(
        taskId: taskId,
        status: 'installing',
        progress: 95,
        message: installResult.message,
      );
      exit(0);
    }

    await _reportTask(
      taskId: taskId,
      status: 'completed',
      progress: 100,
      message: installResult.message,
    );
    await _stateStore.markCompleted(release.version);
    _addEvent(
      DesktopUpdateEvent.completed(
        taskId: taskId,
        message: installResult.message,
      ),
    );
  }

  Future<void> retryFailedUpdate() async {
    final state = await _stateStore.load();
    final hasPreparedArtifact =
        state.artifactPath != null &&
        state.artifactPath!.trim().isNotEmpty &&
        File(state.artifactPath!).existsSync();
    if (hasPreparedArtifact &&
        (state.status == 'failed' || state.status == 'downloaded')) {
      await restartToApplyPreparedUpdate();
      return;
    }
    await checkNow();
  }

  Future<String> _loadOrCreateDeviceUid() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceUidKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final created = _generateDeviceUid();
    await prefs.setString(_deviceUidKey, created);
    return created;
  }

  bool _sameVersion(String left, String right) {
    return left.trim().toLowerCase() == right.trim().toLowerCase();
  }

  int _mapDownloadProgress(int received, int total) {
    if (total <= 0 || received <= 0) {
      return 10;
    }
    final ratio = received / total;
    return (5 + (ratio * 45)).round().clamp(5, 50);
  }

  String _generateDeviceUid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'dev-$hex';
  }

  Future<String> _resolveAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '1.0.0';
    }
  }

  Future<String> _resolveDeviceName() async {
    final host = _resolveHostName();
    if (host.isNotEmpty) {
      return host;
    }
    return 'Desktop-${Platform.operatingSystem}';
  }

  String _resolveHostName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }

  String _resolveArchitecture() {
    final version = Platform.version.toLowerCase();
    if (version.contains('x64') || version.contains('amd64')) {
      return 'x64';
    }
    if (version.contains('arm64')) {
      return 'arm64';
    }
    return 'unknown';
  }

  Future<String?> _resolvePrimaryLocalIpv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final address in iface.addresses) {
          if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
            continue;
          }
          final value = address.address.trim();
          if (value.isNotEmpty) {
            return value;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _resolveBranchCode(AppUser user) {
    final source = user.branchCode.trim().toLowerCase();
    if (source.isEmpty) {
      return 'main';
    }
    return source;
  }

  Future<String> _calculateFileSha256(String filePath) async {
    final digestSink = _DigestSink();
    final input = sha256.startChunkedConversion(digestSink);
    await for (final chunk in File(filePath).openRead()) {
      input.add(chunk);
    }
    input.close();
    return digestSink.value?.toString() ?? '';
  }

  ManagedUpdateRelease? _releaseFromState(DesktopUpdateState state) {
    final releaseId = state.releaseId?.trim();
    final version = state.targetVersion?.trim();
    if (releaseId == null ||
        releaseId.isEmpty ||
        version == null ||
        version.isEmpty) {
      return null;
    }

    return ManagedUpdateRelease(
      id: releaseId,
      version: version,
      buildNumber: null,
      channel: 'stable',
      platform: 'desktop_windows',
      notes: '',
      mandatory: false,
      isEnabled: true,
      installerKind: state.installerKind?.trim().isNotEmpty == true
          ? state.installerKind!.trim()
          : 'zip',
      packageType: state.packageType?.trim().isNotEmpty == true
          ? state.packageType!.trim()
          : 'full',
      packageLayout: state.packageLayout?.trim().isNotEmpty == true
          ? state.packageLayout!.trim()
          : 'bundle_zip',
      entryExecutable: state.entryExecutable?.trim().isNotEmpty == true
          ? state.entryExecutable!.trim()
          : 'iSmartMessenger.exe',
      minSupportedVersion: null,
      targetArchitecture: 'x64',
      minWindowsBuild: null,
      rolloutPercentage: 100,
      silentInstallArgs: state.silentInstallArgs ?? '',
      checksumSha256: state.artifactSha256,
      fileName: state.fileName,
      fileSize: 0,
      downloadPath: null,
      downloadUrl: null,
      externalDownloadUrl: null,
      createdAt: null,
    );
  }

  Future<_InstallerResult> _runInstaller({
    required String taskId,
    required String artifactPath,
    required ManagedUpdateRelease release,
  }) async {
    final resolvedKind = await _detectArtifactKind(artifactPath, release);
    final invocation = _buildInstallerInvocation(
      artifactPath,
      release,
      resolvedKind: resolvedKind,
    );
    if (invocation == null) {
      return _InstallerResult(
        success: false,
        message:
            'Unsupported artifact type. installerKind=${release.installerKind}, packageLayout=${release.packageLayout}, file=${path.basename(artifactPath)}',
      );
    }

    if (_looksLikePlainDesktopExecutable(artifactPath, invocation.kind)) {
      return const _InstallerResult(
        success: false,
        message:
            'ملف التحديث المرفوع يبدو أنه ملف تشغيل التطبيق نفسه وليس installer لويندوز. استخدم MSI أو setup EXE صامت حقيقي.',
      );
    }

    if (Platform.isWindows) {
      return _launchDetachedWindowsInstaller(
        artifactPath: artifactPath,
        release: release,
        invocation: invocation,
      );
    }

    final result = await _runProcessWithTimeout(
      invocation.executable,
      invocation.attempts.first,
      timeout: const Duration(minutes: 20),
    );
    if (result.exitCode == 0) {
      return const _InstallerResult(
        success: true,
        message: 'Update installed successfully.',
      );
    }
    return _InstallerResult(
      success: false,
      message:
          'Installer exited with code ${result.exitCode}. ${result.stderr ?? ''}',
    );
  }

  Future<String> _detectArtifactKind(
    String artifactPath,
    ManagedUpdateRelease release,
  ) async {
    final explicitKind = release.installerKind.trim().toLowerCase();
    if (explicitKind == 'msi' ||
        explicitKind == 'exe' ||
        explicitKind == 'zip') {
      return explicitKind;
    }

    final ext = path.extension(artifactPath).toLowerCase();
    if (ext == '.msi' || ext == '.exe' || ext == '.zip') {
      return ext.replaceFirst('.', '');
    }

    if (release.packageLayout.trim().toLowerCase() == 'bundle_zip') {
      return 'zip';
    }

    try {
      final bytes = await File(artifactPath).openRead(0, 4).first;
      if (bytes.length >= 4 &&
          bytes[0] == 0x50 &&
          bytes[1] == 0x4B &&
          (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07) &&
          (bytes[3] == 0x04 || bytes[3] == 0x06 || bytes[3] == 0x08)) {
        return 'zip';
      }
      if (bytes.length >= 2 && bytes[0] == 0x4D && bytes[1] == 0x5A) {
        return 'exe';
      }
    } catch (_) {}

    return 'unknown';
  }

  _InstallerInvocation? _buildInstallerInvocation(
    String artifactPath,
    ManagedUpdateRelease release, {
    required String resolvedKind,
  }) {
    final kind = resolvedKind;
    final args = _splitArgs(release.silentInstallArgs);

    if (kind == 'msi') {
      return _InstallerInvocation(
        kind: kind,
        executable: 'msiexec.exe',
        attempts: <List<String>>[
          <String>['/i', artifactPath, '/qn', '/norestart', ...args],
        ],
      );
    }

    if (kind == 'exe') {
      final attempts = <List<String>>[
        if (args.isNotEmpty) args,
        const <String>[
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/SP-',
        ],
        const <String>['/S'],
        const <String>['/silent'],
        const <String>['/quiet'],
        const <String>['/qn'],
        const <String>['-s'],
        const <String>['--silent'],
      ];

      final uniqueAttempts = <List<String>>[];
      final seen = <String>{};
      for (final attempt in attempts) {
        final key = attempt.join(' ').trim();
        if (!seen.add(key)) {
          continue;
        }
        uniqueAttempts.add(attempt);
      }

      return _InstallerInvocation(
        kind: kind,
        executable: artifactPath,
        attempts: uniqueAttempts,
      );
    }

    if (kind == 'zip') {
      return _InstallerInvocation(
        kind: kind,
        executable: artifactPath,
        attempts: const <List<String>>[<String>[]],
      );
    }

    return null;
  }

  bool _looksLikePlainDesktopExecutable(String artifactPath, String kind) {
    if (!Platform.isWindows || kind != 'exe') {
      return false;
    }
    final artifactName = path.basename(artifactPath).trim().toLowerCase();
    final currentExecutableName = path
        .basename(Platform.resolvedExecutable)
        .trim()
        .toLowerCase();
    if (artifactName.isEmpty || currentExecutableName.isEmpty) {
      return false;
    }
    return artifactName == currentExecutableName;
  }

  Future<_InstallerResult> _launchDetachedWindowsInstaller({
    required String artifactPath,
    required ManagedUpdateRelease release,
    required _InstallerInvocation invocation,
  }) async {
    final helperExecutablePath = path.join(
      path.dirname(Platform.resolvedExecutable),
      'ismart_messenger_updater.exe',
    );
    if (!File(helperExecutablePath).existsSync()) {
      return const _InstallerResult(
        success: false,
        message: 'Windows update helper was not found next to the app.',
      );
    }

    await DesktopUpdatePaths.ensureInitialized();
    final runtimeHelperPath = path.join(
      DesktopUpdatePaths.runtimeHelperRoot,
      'ismart_messenger_updater_runtime_${DateTime.now().millisecondsSinceEpoch}.exe',
    );
    await File(helperExecutablePath).copy(runtimeHelperPath);

    final arguments = <String>[
      '--parent-pid',
      pid.toString(),
      '--installer-path',
      artifactPath,
      '--installer-kind',
      invocation.kind,
      '--silent-args',
      release.silentInstallArgs,
      '--relaunch-path',
      Platform.resolvedExecutable,
      '--install-dir',
      path.dirname(Platform.resolvedExecutable),
      '--backup-dir',
      DesktopUpdatePaths.backupRoot,
      '--log-dir',
      DesktopUpdatePaths.logsRoot,
      '--target-version',
      release.version,
      '--state-file',
      DesktopUpdatePaths.stateFilePath,
      '--result-file',
      DesktopUpdatePaths.helperResultFilePath,
    ];

    final helperProcess = await Process.start(
      runtimeHelperPath,
      arguments,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    if (helperProcess.pid <= 0) {
      return const _InstallerResult(
        success: false,
        message: 'Failed to start automatic installer helper.',
      );
    }

    return const _InstallerResult(
      success: true,
      message: 'Updating application now. The app will reopen automatically.',
      completionHandledExternally: true,
    );
  }

  List<String> _splitArgs(String raw) {
    final source = raw.trim();
    if (source.isEmpty) {
      return const <String>[];
    }
    return source
        .split(RegExp(r'\s+'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  Future<ProcessResult> _runProcessWithTimeout(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: true,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .listen(stdoutBuffer.write, onError: (_) {});
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write, onError: (_) {});

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await Future.wait([stdoutSub.cancel(), stderrSub.cancel()]);
      return ProcessResult(
        process.pid,
        -1,
        stdoutBuffer.toString(),
        'Process timeout after ${timeout.inMinutes} minutes. ${stderrBuffer.toString()}',
      );
    }

    await Future.wait([stdoutSub.cancel(), stderrSub.cancel()]);
    return ProcessResult(
      process.pid,
      exitCode,
      stdoutBuffer.toString(),
      stderrBuffer.toString(),
    );
  }
}

class _InstallerInvocation {
  const _InstallerInvocation({
    required this.kind,
    required this.executable,
    required this.attempts,
  });

  final String kind;
  final String executable;
  final List<List<String>> attempts;
}

class _InstallerResult {
  const _InstallerResult({
    required this.success,
    required this.message,
    this.completionHandledExternally = false,
  });

  final bool success;
  final String message;
  final bool completionHandledExternally;
}

class _QueuedTaskReport {
  const _QueuedTaskReport({
    required this.taskId,
    required this.status,
    required this.progress,
    required this.message,
  });

  final String taskId;
  final String status;
  final int progress;
  final String message;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
