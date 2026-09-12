import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../shared/models/app_user.dart';
import '../models/update_models.dart';
import '../services/update_check_service.dart';

class MobileUpdateEvent {
  const MobileUpdateEvent({
    required this.type,
    this.release,
    this.task,
    this.deviceUid,
    this.isMandatory = false,
    this.message = '',
  });

  final String type; // 'update_available', 'update_forced', 'check_error'
  final MobileUpdateRelease? release;
  final MobileUpdateTask? task;
  final String? deviceUid;
  final bool isMandatory;
  final String message;
}

class MobileUpdateAgent {
  MobileUpdateAgent(this._updateCheckService);

  static const _deviceUidKey = 'mobile_update_device_uid';
  static const _lastOfferedTaskIdKey = 'mobile_update_last_offered_task_id';
  static const deviceUidStorageKey = _deviceUidKey;

  final UpdateCheckService _updateCheckService;
  final StreamController<MobileUpdateEvent> _eventsController =
      StreamController<MobileUpdateEvent>.broadcast();

  bool _disposed = false;
  AppUser? _currentUser;
  String? _deviceUid;
  String? _lastOfferedTaskId;

  Stream<MobileUpdateEvent> get events => _eventsController.stream;

  Future<void> initialize() async {
    _deviceUid ??= await _loadOrCreateDeviceUid();
    _lastOfferedTaskId = await _loadLastOfferedTaskId();
  }

  Future<void> start(AppUser user) async {
    if (_disposed) {
      debugPrint('[MobileUpdateAgent] Agent disposed, cannot start');
      return;
    }
    _currentUser = user;
    debugPrint(
      '[MobileUpdateAgent] Starting for user: ${user.username} (branch: ${user.branchCode})',
    );

    debugPrint(
      '[MobileUpdateAgent] Ready for event-driven update checks (no periodic timer)',
    );
  }

  Future<void> stop() async {
    debugPrint('[MobileUpdateAgent] Stopping update checks');
    _currentUser = null;
  }

  Future<void> dispose() async {
    debugPrint('[MobileUpdateAgent] Disposing agent');
    _disposed = true;
    await stop();
    await _eventsController.close();
  }

  Future<void> clearUpdateState() async {
    debugPrint('[MobileUpdateAgent] Clearing update state (logout)');
    _lastOfferedTaskId = null;
    await _deleteLastOfferedTaskId();
  }

  Future<void> checkNow({bool forceEmitExistingTask = false}) async {
    if (_currentUser == null || _deviceUid == null) {
      return;
    }
    await _checkForUpdates(forceEmitExistingTask: forceEmitExistingTask);
  }

  Future<void> _checkForUpdates({bool forceEmitExistingTask = false}) async {
    if (_currentUser == null || _deviceUid == null) {
      return;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final branchCode = _currentUser?.branchCode ?? 'main';

      debugPrint(
        '[MobileUpdateAgent] Checking for updates (version: ${packageInfo.version}, branch: $branchCode)',
      );

      final response = await _updateCheckService.checkForUpdates(
        deviceUid: _deviceUid!,
        currentVersion: packageInfo.version,
        branchCode: branchCode,
      );

      if (response.requiresUpdate && response.availableRelease != null) {
        final releaseVersion = response.availableRelease!.version;
        final taskId = response.currentTask?.id ?? '';
        debugPrint(
          '[MobileUpdateAgent] Update available: $releaseVersion (mandatory: ${response.isMandatory})',
        );

        // Emit when task is new, or when forced update is required.
        if (response.isMandatory ||
            forceEmitExistingTask ||
            taskId != _lastOfferedTaskId) {
          _lastOfferedTaskId = taskId;
          if (taskId.isNotEmpty) {
            await _saveLastOfferedTaskId(taskId);
          }

          if (response.isMandatory) {
            debugPrint('[MobileUpdateAgent] Emitting forced update event');
            _eventsController.add(
              MobileUpdateEvent(
                type: 'update_forced',
                release: response.availableRelease,
                task: response.currentTask,
                deviceUid: _deviceUid,
                isMandatory: true,
                message: 'يجب تحديث التطبيق للمتابعة',
              ),
            );
          } else {
            debugPrint('[MobileUpdateAgent] Emitting update available event');
            _eventsController.add(
              MobileUpdateEvent(
                type: 'update_available',
                release: response.availableRelease,
                task: response.currentTask,
                deviceUid: _deviceUid,
                isMandatory: false,
                message: 'يوجد إصدار جديد من التطبيق',
              ),
            );
          }
        } else {
          debugPrint('[MobileUpdateAgent] Task already offered, skipping');
        }
      } else {
        debugPrint('[MobileUpdateAgent] No update available');
      }
    } catch (e) {
      debugPrint('[MobileUpdateAgent] Error checking for updates: $e');
      _eventsController.add(
        MobileUpdateEvent(type: 'check_error', message: 'خطأ في فحص التحديثات'),
      );
    }
  }

  Future<String> _loadOrCreateDeviceUid() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceUidKey);

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final created = const Uuid().v4();
    await prefs.setString(_deviceUidKey, created);
    return created;
  }

  Future<String?> _loadLastOfferedTaskId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastOfferedTaskIdKey);
  }

  Future<void> _saveLastOfferedTaskId(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastOfferedTaskIdKey, taskId);
    debugPrint('[MobileUpdateAgent] Saved last offered task: $taskId');
  }

  Future<void> _deleteLastOfferedTaskId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastOfferedTaskIdKey);
    debugPrint('[MobileUpdateAgent] Deleted last offered task');
  }

  String? get deviceUid => _deviceUid;
}
