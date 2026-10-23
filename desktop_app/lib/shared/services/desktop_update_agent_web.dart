import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/admin/data/update_management_repository.dart';
import '../../features/admin/models/update_management_models.dart';
import '../models/app_user.dart';
import 'desktop_update_state.dart';
import 'desktop_update_state_store_web.dart';
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

  factory DesktopUpdateEvent.updateAvailable({
    required String version,
    required String message,
    String? taskId,
  }) {
    return DesktopUpdateEvent(
      type: 'update_available',
      taskId: taskId,
      status: 'available',
      message: message,
      progress: 0,
    );
  }
}

class DesktopUpdateAgent {
  DesktopUpdateAgent(this._repository, this._stateStore);

  static const _deviceUidKey = 'desktop_update_device_uid';
  static const _progressReportStepPercent = 5;

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
  int _lastProgressReported = -1;
  String? _lastReportedStatus;

  final ValueNotifier<bool> hasPreparedUpdateNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> hasUpdateAvailableNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double?> downloadProgressNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<String?> statusMessageNotifier = ValueNotifier<String?>(null);

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
    _deviceUid ??= await _loadOrCreateDeviceUid();

    if (web_bridge.isElectron()) {
      await _reconcilePostRestartState();
      await _emitPreparedUpdateStateIfNeeded();
      // Register our device and LAN IP once on startup/login without background timers:
      unawaited(_runHeartbeat());
    }
  }

  Future<void> checkNow() async {
    await _runHeartbeat();
  }

  Future<DeviceHeartbeatResponse?> checkNowDetailed() async {
    return _runHeartbeat();
  }

  void setConnectionStatus(String status) {
    _connectionStatus = status;
  }

  void stop() {
    _isHeartbeatRunning = false;
    _isTaskRunning = false;
    _currentUser = null;
  }

  void dispose() {
    _disposed = true;
    stop();
    _eventsController.close();
    web_bridge.setElectronUpdaterProgressHandler(null);
  }

  Future<DesktopUpdateState> loadState() => _stateStore.load();

  Future<DeviceHeartbeatResponse?> _runHeartbeat() async {
    if (_disposed ||
        _isHeartbeatRunning ||
        _currentUser == null ||
        !web_bridge.isElectron()) {
      return _lastHeartbeatResponse;
    }
    _isHeartbeatRunning = true;
    try {
      final electronInfo = await web_bridge.getElectronDeviceInfo();
      final appVersion = electronInfo['appVersion']?.toString() ?? '1.1.2';
      _deviceUid ??= await _loadOrCreateDeviceUid();

      String? primaryIp = electronInfo['localIp']?.toString();
      if ((primaryIp == null || primaryIp.trim().isEmpty) &&
          electronInfo['localIps'] is List &&
          (electronInfo['localIps'] as List).isNotEmpty) {
        primaryIp = (electronInfo['localIps'] as List).first?.toString();
      }

      final response = await _repository.heartbeatDevice(
        deviceUid: _deviceUid!,
        deviceName: electronInfo['hostName']?.toString() ?? 'Electron App',
        hostName: electronInfo['hostName']?.toString() ?? 'electron-host',
        localIp: primaryIp,
        branchCode: _currentUser!.branchCode.trim().toLowerCase().isEmpty
            ? 'main'
            : _currentUser!.branchCode.trim().toLowerCase(),
        channel: 'stable',
        platform: 'desktop_windows',
        appVersion: appVersion,
        osName: 'electron-${electronInfo['osName'] ?? 'windows'}',
        osVersion: electronInfo['osVersion']?.toString() ?? 'unknown',
        architecture: electronInfo['architecture']?.toString() ?? 'ia32',
        connectionStatus: _connectionStatus,
        autoUpdateEnabled: true,
        silentInstallEnabled: true,
      );
      _lastHeartbeatResponse = response;
      final hasPending = response.pendingTasks.isNotEmpty;
      final hasNewer = response.latestRelease != null &&
          !_areVersionsEqual(appVersion, response.latestRelease!.version);

      if (hasPending || hasNewer) {
        hasUpdateAvailableNotifier.value = true;
        final targetVer = hasPending
            ? response.pendingTasks.first.release.version
            : response.latestRelease!.version;
        _eventsController.add(
          DesktopUpdateEvent.updateAvailable(
            version: targetVer,
            message: 'يتوفر إصدار جديد (' + targetVer + ') لتطبيق المنظومة.',
            taskId: hasPending ? response.pendingTasks.first.id : null,
          ),
        );
        unawaited(
          web_bridge.showBrowserNotification(
            title: 'تحديث جديد متاح',
            body: 'يتوفر إصدار جديد (' + targetVer + ') لتطبيق المنظومة. انقر للاطلاع عليه.',
          ),
        );
      }

      if (response.pendingTasks.isNotEmpty && !_isTaskRunning) {
        unawaited(_executePendingTask(response.pendingTasks.first));
      }
      return response;
    } catch (error) {
      _eventsController.add(
        DesktopUpdateEvent.heartbeatError(error.toString()),
      );
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

    try {
      final electronInfo = await web_bridge.getElectronDeviceInfo();
      final currentVersion = electronInfo['appVersion']?.toString() ?? '1.1.2';
      final currentState = await _stateStore.load();

      if (_areVersionsEqual(currentVersion, task.release.version)) {
        await _reportTaskProgress(
          taskId: task.id,
          status: 'completed',
          progress: 100,
          message: 'The device is already on version ${task.release.version}.',
        );
        await _stateStore.markCompleted(currentVersion);
        _eventsController.add(
          DesktopUpdateEvent.completed(
            taskId: task.id,
            message: 'تم تفعيل التحديث بالفعل.',
          ),
        );
        return;
      }

      final hasPreparedArtifact =
          currentState.taskId == task.id &&
          currentState.targetVersion == task.release.version &&
          currentState.status == 'downloaded';

      if (hasPreparedArtifact) {
        _eventsController.add(
          DesktopUpdateEvent.readyToRestart(
            taskId: task.id,
            message:
                'تم تنزيل التحديث ${task.release.version}. أعد تشغيل التطبيق عندما يناسبك لإكمال التثبيت.',
          ),
        );
        return;
      }

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
            task.release.fileName ?? 'release-${task.release.version}.zip',
        currentVersion: currentVersion,
      );

      await _reportTaskProgress(
        taskId: task.id,
        status: 'acknowledged',
        progress: 1,
        message: 'Preparing download on Electron...',
      );

      final resolvedUrl =
          (task.release.downloadUrl ?? task.release.externalDownloadUrl ?? '')
              .trim();
      final absoluteUrl = resolvedUrl.startsWith('http')
          ? resolvedUrl
          : '${_repository.baseUrl.replaceAll(RegExp(r'/+$'), '')}${resolvedUrl.startsWith('/') ? '' : '/'}$resolvedUrl';

      final token = await _repository.getAccessToken();

      hasUpdateAvailableNotifier.value = true;
      downloadProgressNotifier.value = 0.0;
      statusMessageNotifier.value = 'جاري بدء تحميل التحديث...';

      web_bridge.setElectronUpdaterProgressHandler((payload) {
        final status = payload['status']?.toString() ?? 'downloading';
        final progress = payload['progress'] is int
            ? payload['progress'] as int
            : int.tryParse(payload['progress']?.toString() ?? '') ?? 0;
        final message = payload['message']?.toString() ?? '';

        downloadProgressNotifier.value = progress / 100.0;
        statusMessageNotifier.value = message;

        if (status == 'downloading') {
          _eventsController.add(
            DesktopUpdateEvent.status(
              taskId: task.id,
              status: 'downloading',
              message: message,
              progress: progress,
            ),
          );
          unawaited(
            _reportTaskProgress(
              taskId: task.id,
              status: 'downloading',
              progress: progress,
              message: message,
            ),
          );
        }
      });

      final downloadResult = await web_bridge.startElectronUpdate(
        downloadUrl: absoluteUrl,
        token: token,
        checksumSha256: task.release.checksumSha256,
      );

      if (downloadResult['success'] != true) {
        throw StateError(
          downloadResult['error']?.toString() ??
              'فشل تحميل التحديث من خلال إلكترون.',
        );
      }

      await _stateStore.markDownloaded(
        artifactPath: downloadResult['zipPath']?.toString() ?? 'app-update.zip',
        artifactSha256: task.release.checksumSha256 ?? '',
      );

      hasPreparedUpdateNotifier.value = true;
      hasUpdateAvailableNotifier.value = true;
      downloadProgressNotifier.value = 1.0;
      statusMessageNotifier.value = 'جاهز لإعادة التشغيل والتثبيت';

      await _reportTaskProgress(
        taskId: task.id,
        status: 'downloading',
        progress: 100,
        message: 'تم تحميل التحديث بالكامل وجاهز لإعادة التشغيل.',
      );

      unawaited(
        web_bridge.showBrowserNotification(
          title: 'اكتمل تحميل التحديث',
          body: 'تم تنزيل الإصدار ' + task.release.version + ' بنجاح. أعد تشغيل التطبيق لإكمال التثبيت.',
        ),
      );

      _eventsController.add(
        DesktopUpdateEvent.readyToRestart(
          taskId: task.id,
          message:
              'تم تنزيل التحديث ${task.release.version}. يمكنك متابعة عملك الآن ثم إعادة تشغيل التطبيق لاحقًا لتثبيته.',
        ),
      );
    } catch (error) {
      await _stateStore.markFailed(error.toString());
      await _reportTaskProgress(
        taskId: task.id,
        status: 'failed',
        progress: 100,
        message: error.toString(),
      );
      _eventsController.add(
        DesktopUpdateEvent.failed(taskId: task.id, message: error.toString()),
      );
    } finally {
      _isTaskRunning = false;
      web_bridge.setElectronUpdaterProgressHandler(null);
    }
  }

  Future<void> _reportTaskProgress({
    required String taskId,
    required String status,
    required int progress,
    required String message,
  }) async {
    if (_deviceUid == null) {
      return;
    }
    final clampedProgress = progress.clamp(0, 100);
    final isTerminalStatus =
        status == 'completed' || status == 'failed' || status == 'cancelled';
    final shouldSend =
        isTerminalStatus ||
        status != _lastReportedStatus ||
        status != 'downloading' ||
        clampedProgress == 0 ||
        clampedProgress == 100 ||
        (clampedProgress - _lastProgressReported).abs() >=
            _progressReportStepPercent;
    if (!shouldSend) {
      return;
    }

    try {
      await _repository.reportTaskProgress(
        taskId: taskId,
        deviceUid: _deviceUid!,
        status: status,
        progress: clampedProgress,
        message: message,
      );
      _lastReportedStatus = status;
      _lastProgressReported = clampedProgress;
    } on DioException {
      // Progress updates are telemetry only. They must not block download,
      // restart, or post-restart reconciliation when the server throttles or
      // the task was already finalized.
    }
  }

  Future<bool> hasPreparedUpdate() async {
    final taskState = await _stateStore.load();
    final isReady = taskState.status == 'downloaded';
    hasPreparedUpdateNotifier.value = isReady;
    return isReady;
  }

  Future<void> downloadRelease(ManagedUpdateRelease release) async {
    if (_isTaskRunning) return;
    _isTaskRunning = true;
    try {
      final electronInfo = await web_bridge.getElectronDeviceInfo();
      final currentVersion = electronInfo['appVersion']?.toString() ?? '1.1.2';

      hasUpdateAvailableNotifier.value = true;
      downloadProgressNotifier.value = 0.0;
      statusMessageNotifier.value = 'جاري بدء تحميل التحديث...';

      await _stateStore.markDownloading(
        taskId: 'manual_' + release.id,
        releaseId: release.id,
        targetVersion: release.version,
        packageType: release.packageType,
        installerKind: release.installerKind,
        packageLayout: release.packageLayout,
        entryExecutable: release.entryExecutable,
        silentInstallArgs: release.silentInstallArgs,
        fileName: release.fileName ?? ('release-' + release.version + '.zip'),
        currentVersion: currentVersion,
      );

      final resolvedUrl = (release.downloadUrl ?? release.externalDownloadUrl ?? '').trim();
      final base = _repository.baseUrl;
      final absoluteUrl = resolvedUrl.startsWith('http')
          ? resolvedUrl
          : (base.endsWith('/') ? base : base + '/') + (resolvedUrl.startsWith('/') ? resolvedUrl.substring(1) : resolvedUrl);
      final token = await _repository.getAccessToken();

      web_bridge.setElectronUpdaterProgressHandler((payload) {
        final progress = payload['progress'] is int
            ? payload['progress'] as int
            : int.tryParse(payload['progress']?.toString() ?? '') ?? 0;
        final message = payload['message']?.toString() ?? '';
        downloadProgressNotifier.value = progress / 100.0;
        statusMessageNotifier.value = message;
      });

      final downloadResult = await web_bridge.startElectronUpdate(
        downloadUrl: absoluteUrl,
        token: token,
        checksumSha256: release.checksumSha256,
      );

      if (downloadResult['success'] != true) {
        throw StateError(downloadResult['error']?.toString() ?? 'فشل تحميل التحديث.');
      }

      await _stateStore.markDownloaded(
        artifactPath: downloadResult['zipPath']?.toString() ?? 'app-update.zip',
        artifactSha256: release.checksumSha256 ?? '',
      );

      hasPreparedUpdateNotifier.value = true;
      hasUpdateAvailableNotifier.value = true;
      downloadProgressNotifier.value = 1.0;
      statusMessageNotifier.value = 'تم تحميل التحديث بنجاح وجاهز للتثبيت.';

      unawaited(
        web_bridge.showBrowserNotification(
          title: 'اكتمل تنزيل التحديث',
          body: 'الإصدار ' + release.version + ' جاهز للتثبيت عند إعادة التشغيل.',
        ),
      );

      _eventsController.add(
        DesktopUpdateEvent.readyToRestart(
          taskId: 'manual_' + release.id,
          message: 'تم تنزيل التحديث ' + release.version + '. يمكنك إعادة تشغيل التطبيق لتثبيته.',
        ),
      );
    } catch (e) {
      statusMessageNotifier.value = 'فشل تحميل التحديث: ' + e.toString();
      downloadProgressNotifier.value = null;
      rethrow;
    } finally {
      _isTaskRunning = false;
    }
  }

  Future<void> restartToApplyPreparedUpdate() async {
    final state = await _stateStore.load();
    if (state.status != 'downloaded') {
      throw StateError('لا توجد حزمة تحديث جاهزة للتثبيت على هذا الجهاز.');
    }
    final taskId = state.taskId?.trim();
    if (taskId != null && taskId.isNotEmpty && !taskId.startsWith('manual_')) {
      await _reportTaskProgress(
        taskId: taskId,
        status: 'installing',
        progress: 80,
        message: 'يتم الآن إغلاق التطبيق لتثبيت التحديث تلقائياً.',
      );
    }
    await _stateStore.markInstalling();

    final installResult = await web_bridge.applyElectronUpdate();
    if (installResult['success'] != true) {
      final errMsg =
          installResult['error']?.toString() ?? 'فشل تطبيق التحديث في إلكترون.';
      await _stateStore.markFailed(errMsg);
      if (taskId != null && taskId.isNotEmpty && !taskId.startsWith('manual_')) {
        await _reportTaskProgress(
          taskId: taskId,
          status: 'failed',
          progress: 100,
          message: errMsg,
        );
      }
      _eventsController.add(
        DesktopUpdateEvent.failed(taskId: taskId ?? 'unknown', message: errMsg),
      );
      return;
    }

    await _stateStore.markAwaitingHealthcheck();
  }

  Future<void> retryFailedUpdate() async {
    final state = await _stateStore.load();
    if (state.status == 'failed' || state.status == 'downloaded') {
      if (state.status == 'downloaded') {
        await restartToApplyPreparedUpdate();
        return;
      }
    }
    await checkNow();
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

    final electronInfo = await web_bridge.getElectronDeviceInfo();
    final currentVersion = electronInfo['appVersion']?.toString() ?? '1.1.2';

    if (taskState.status == 'awaiting_healthcheck') {
      if (_areVersionsEqual(currentVersion, targetVersion)) {
        await _reportTaskProgress(
          taskId: taskId,
          status: 'completed',
          progress: 100,
          message:
              'Update $targetVersion was confirmed successfully after restart.',
        );
        await _stateStore.markCompleted(currentVersion);
        _eventsController.add(
          DesktopUpdateEvent.completed(
            taskId: taskId,
            message: 'تم تفعيل الإصدار الجديد بنجاح.',
          ),
        );
      } else {
        final message =
            'تمت إعادة تشغيل التطبيق ولكن لم يتم الانتقال للإصدار المستهدف $targetVersion. الإصدار الحالي: $currentVersion.';
        await _reportTaskProgress(
          taskId: taskId,
          status: 'failed',
          progress: 100,
          message: message,
        );
        await _stateStore.markRolledBack(message);
      }
    }
  }

  Future<void> _emitPreparedUpdateStateIfNeeded() async {
    final taskState = await _stateStore.load();
    final taskId = taskState.taskId?.trim();
    if (taskId == null || taskId.isEmpty) {
      return;
    }

    if (taskState.status == 'downloaded') {
      _eventsController.add(
        DesktopUpdateEvent.readyToRestart(
          taskId: taskId,
          message:
              'يوجد تحديث جاهز للتثبيت بالفعل. أعد تشغيل التطبيق عندما يناسبك.',
        ),
      );
    }
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

  String _generateDeviceUid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return 'dev-${bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
  }

  bool _areVersionsEqual(String v1, String v2) {
    String clean(String v) {
      final base = v.split('+').first;
      return base.replaceAll(RegExp(r'\s+'), '').toLowerCase().trim();
    }

    return clean(v1) == clean(v2);
  }
}
