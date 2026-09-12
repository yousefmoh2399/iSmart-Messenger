import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../../core/utils/formatters.dart';
import '../../shared/models/update_models.dart';
import '../../shared/providers/providers.dart';
import 'button_loading_indicator.dart';

class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({
    super.key,
    required this.release,
    this.task,
    this.deviceUid,
    required this.isMandatory,
    required this.onUpdate,
    required this.onLater,
  });

  final MobileUpdateRelease release;
  final MobileUpdateTask? task;
  final String? deviceUid;
  final bool isMandatory;
  final VoidCallback onUpdate;
  final VoidCallback? onLater;

  static Future<bool?> show(
    BuildContext context, {
    required MobileUpdateRelease release,
    MobileUpdateTask? task,
    String? deviceUid,
    required bool isMandatory,
    required VoidCallback onUpdate,
    VoidCallback? onLater,
  }) {
    return showDialog<bool>(
      context: context,
      // Dismiss is controlled from inside the dialog buttons/back behavior.
      // This prevents accidental close while update download is running.
      barrierDismissible: false,
      builder: (_) => UpdateDialog(
        release: release,
        task: task,
        deviceUid: deviceUid,
        isMandatory: isMandatory,
        onUpdate: onUpdate,
        onLater: onLater ?? () => Navigator.pop(context, false),
      ),
    );
  }

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  static const _pendingInstallPathKey = 'mobile_update_pending_install_path';
  static const _pendingInstallVersionKey =
      'mobile_update_pending_install_version';
  static const _pendingInstallTaskIdKey =
      'mobile_update_pending_install_task_id';
  static const MethodChannel _installerChannel = MethodChannel('app.installer');
  late bool _isDownloading;
  late bool _isInstallerPending;
  late int _downloadProgress;
  late String? _currentStatus;
  late int _retryCount;
  String? _downloadedFilePath;
  static const int _maxRetries = 3;
  static const int _retryDelaySeconds = 2;
  static const int _progressReportIntervalMs = 1500;
  static const int _progressReportStepPercent = 5;
  static const int _installVerificationAttempts = 24; // ~2 minutes
  static const Duration _installVerificationInterval = Duration(seconds: 5);
  int _lastReportedProgress = -1;
  DateTime? _lastReportedAt;
  String? _lastReportedStatus;
  bool _isReportingProgress = false;

  @override
  void initState() {
    super.initState();
    _isDownloading = false;
    _isInstallerPending = false;
    _downloadProgress = 0;
    _currentStatus = null;
    _retryCount = 0;
    debugPrint(
      '[UpdateDialog] Initialized for version ${widget.release.version}',
    );
    unawaited(_restorePendingInstallerState());
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;

    return WillPopScope(
      onWillPop: () async {
        if (widget.isMandatory || _isDownloading) {
          return false;
        }
        return true;
      },
      child: AlertDialog(
        title: const Text('تحديث متاح'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إصدار ${release.version}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (release.notes.isNotEmpty) ...[
                  Text(
                    'التغييرات:',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    release.notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isMandatory)
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_rounded,
                              color: Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'هذا التحديث إجباري',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      if (widget.isMandatory) const SizedBox(height: 8),
                      Text(
                        'حجم الملف: ${formatFileSize(release.fileSize)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'تاريخ الإصدار: ${release.createdAt == null ? "-" : formatDate(release.createdAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_isDownloading) ...[
                  const SizedBox(height: 12),
                  if (_currentStatus != null) ...[
                    Text(
                      _currentStatus!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                  LinearProgressIndicator(
                    value: _downloadProgress / 100,
                    minHeight: 6,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '$_downloadProgress%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (!widget.isMandatory && !_isDownloading)
            TextButton(
              onPressed: () {
                widget.onLater?.call();
                Navigator.pop(context, false);
              },
              child: const Text('لاحقاً'),
            ),
          FilledButton.icon(
            onPressed: _isDownloading
                ? null
                : (_isInstallerPending
                      ? (_downloadedFilePath == null
                            ? null
                            : () => _openInstallerFromButton(
                                _downloadedFilePath!,
                              ))
                      : _handleUpdate),
            icon: _isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: ButtonLoadingIndicator(),
                  )
                : Icon(
                    _isInstallerPending
                        ? Icons.system_update_alt_rounded
                        : Icons.download_rounded,
                  ),
            label: Text(
              _isDownloading
                  ? 'جاري التنزيل...'
                  : (_isInstallerPending ? 'فتح شاشة التثبيت' : 'تحديث الآن'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdate() async {
    if (_isInstallerPending && _downloadedFilePath != null) {
      await _launchInstaller(_downloadedFilePath!);
      return;
    }
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _currentStatus = 'جاري التنزيل...';
      _retryCount = 0;
    });

    try {
      final release = widget.release;
      await _reportProgress(
        status: 'acknowledged',
        progress: 0,
        message: 'Update acknowledged by user',
      );

      // Determine download URL
      final downloadUrl = release.externalDownloadUrl ?? release.downloadUrl;
      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception('لا يوجد رابط تحميل للإصدار');
      }

      // Get app cache directory for storing APK
      final cacheDir = await getTemporaryDirectory();
      final fileName = release.fileName ?? 'update.apk';
      final filePath = '${cacheDir.path}/$fileName';
      final file = File(filePath);
      _downloadedFilePath = filePath;

      // Delete old file if exists
      if (file.existsSync()) {
        await file.delete();
        debugPrint('[UpdateDialog] Deleted old APK file');
      }

      // Download with retry logic
      await _reportProgress(
        status: 'downloading',
        progress: 1,
        message: 'Starting download',
      );
      await _downloadWithRetry(downloadUrl, filePath);

      if (!file.existsSync()) {
        throw Exception('فشل حفظ ملف التحديث');
      }
      await _savePendingInstallerState(filePath);

      // Update status
      if (mounted) {
        setState(() => _currentStatus = 'جاري التثبيت...');
      }
      await _reportProgress(
        status: 'installing',
        progress: 100,
        message: 'Launching installer',
      );

      debugPrint('[UpdateDialog] APK downloaded, attempting installation');

      // Install APK
      await _launchInstaller(filePath);
    } catch (e) {
      await _reportProgress(
        status: 'failed',
        progress: _downloadProgress,
        message: e.toString(),
      );
      debugPrint('[UpdateDialog] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في التحديث: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
          _currentStatus = null;
        });
      }
    }
  }

  Future<void> _downloadWithRetry(String downloadUrl, String filePath) async {
    while (_retryCount < _maxRetries) {
      try {
        debugPrint(
          '[UpdateDialog] Attempt ${_retryCount + 1} of $_maxRetries to download',
        );
        await _performDownload(downloadUrl, filePath);
        debugPrint('[UpdateDialog] Download successful');
        return;
      } on DioException catch (e) {
        _retryCount++;

        // Token refresh is now handled automatically by the ApiClient interceptor
        // If we get 401 here, it means refresh failed and user needs to login again
        if (e.response?.statusCode == 401) {
          debugPrint(
            '[UpdateDialog] Token refresh failed, user needs to login again',
          );
          rethrow;
        }

        // Other errors - retry with backoff
        if (_retryCount < _maxRetries) {
          debugPrint(
            '[UpdateDialog] Download failed (attempt $_retryCount): ${e.message}',
          );
          final delaySeconds = _retryDelaySeconds * _retryCount;

          if (mounted) {
            setState(
              () => _currentStatus = 'إعادة محاولة خلال $delaySeconds ثانية...',
            );
          }

          await Future<void>.delayed(Duration(seconds: delaySeconds));
        } else {
          debugPrint('[UpdateDialog] Max retries reached');
          rethrow;
        }
      }
    }
  }

  Future<void> _performDownload(String downloadUrl, String filePath) async {
    final apiClient = ref.read(authenticatedApiClientProvider);
    await apiClient.dio.download(
      downloadUrl,
      filePath,
      onReceiveProgress: (received, total) {
        if (mounted) {
          final progress = total > 0 ? ((received / total) * 100).toInt() : 0;
          setState(() {
            _downloadProgress = progress;
          });
          _reportProgress(status: 'downloading', progress: progress);
        }
      },
    );
  }

  Future<void> _installApkUsingIntent(String filePath) async {
    try {
      final canInstallUnknownApps =
          await _installerChannel.invokeMethod<bool>('canInstallUnknownApps') ??
          false;
      if (!canInstallUnknownApps) {
        await _installerChannel.invokeMethod('openUnknownAppsSettings');
        throw Exception(
          'يجب السماح بالتثبيت من هذا المصدر أولاً، ثم اضغط "فتح شاشة التثبيت" مرة أخرى.',
        );
      }
      await _installerChannel.invokeMethod('installApk', {'apkPath': filePath});
    } catch (e) {
      debugPrint('[UpdateDialog] APK install failed: $e');
      rethrow;
    }
  }

  Future<void> _launchInstaller(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      await _clearPendingInstallerState();
      if (!mounted) return;
      setState(() {
        _isInstallerPending = false;
        _downloadedFilePath = null;
        _currentStatus =
            'ملف التحديث لم يعد موجودًا على الجهاز. اضغط "تحديث الآن" لتنزيله مرة أخرى.';
      });
      return;
    }
    await _installApkUsingIntent(filePath);
    debugPrint('[UpdateDialog] Installer launched, waiting for version change');
    if (!mounted) {
      return;
    }
    setState(() {
      _isDownloading = false;
      _isInstallerPending = true;
      _currentStatus =
          'تم فتح شاشة التثبيت. بعد اكتمال التثبيت سنغلق النافذة تلقائيًا.';
    });
    await _waitForInstalledVersion();
  }

  Future<void> _openInstallerFromButton(String filePath) async {
    try {
      await _launchInstaller(filePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر فتح شاشة التثبيت. تأكد من السماح بتثبيت التطبيقات من هذا المصدر ثم حاول مرة أخرى.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _currentStatus =
            'تعذر فتح شاشة التثبيت. اضغط مرة أخرى بعد منح الصلاحية.';
      });
    }
  }

  Future<void> _waitForInstalledVersion() async {
    final targetVersion = widget.release.version.trim();
    if (targetVersion.isEmpty) {
      return;
    }
    for (var i = 0; i < _installVerificationAttempts; i++) {
      await Future<void>.delayed(_installVerificationInterval);
      if (!mounted) {
        return;
      }
      try {
        final info = await PackageInfo.fromPlatform();
        final currentVersion = info.version.trim();
        if (currentVersion == targetVersion) {
          await _reportProgress(
            status: 'completed',
            progress: 100,
            message: 'Update installed successfully',
          );
          if (!mounted) {
            return;
          }
          widget.onUpdate();
          await _clearPendingInstallerState();
          if (!mounted) {
            return;
          }
          Navigator.pop(context, true);
          return;
        }
      } catch (_) {
        // ignore transient read failures
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _currentStatus =
          'تم تنزيل التحديث، لكن لم يتم تأكيد اكتمال التثبيت بعد. أكمل التثبيت من الشاشة التي فُتحت أو اضغط "فتح شاشة التثبيت".';
    });
  }

  Future<void> _reportProgress({
    required String status,
    required int progress,
    String? message,
  }) async {
    final task = widget.task;
    final deviceUid = widget.deviceUid;
    if (task == null ||
        task.id.isEmpty ||
        deviceUid == null ||
        deviceUid.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final isTerminalStatus =
        status == 'completed' || status == 'failed' || status == 'cancelled';
    final statusChanged = _lastReportedStatus != status;
    final progressDelta = (progress - _lastReportedProgress).abs();
    final enoughProgressDelta = progressDelta >= _progressReportStepPercent;
    final enoughTimePassed =
        _lastReportedAt == null ||
        now.difference(_lastReportedAt!).inMilliseconds >=
            _progressReportIntervalMs;

    final shouldSend =
        isTerminalStatus ||
        statusChanged ||
        progress == 0 ||
        progress == 100 ||
        (enoughProgressDelta && enoughTimePassed);
    if (!shouldSend || _isReportingProgress) {
      return;
    }

    _lastReportedStatus = status;
    _lastReportedProgress = progress;
    _lastReportedAt = now;
    _isReportingProgress = true;
    try {
      await ref
          .read(updateCheckServiceProvider)
          .reportTaskProgress(
            taskId: task.id,
            status: status,
            progress: progress,
            message: message,
            deviceUid: deviceUid,
          );
    } finally {
      _isReportingProgress = false;
    }
  }

  Future<void> _restorePendingInstallerState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedVersion = prefs.getString(_pendingInstallVersionKey) ?? '';
    final savedPath = prefs.getString(_pendingInstallPathKey) ?? '';
    final savedTaskId = prefs.getString(_pendingInstallTaskIdKey) ?? '';
    final currentTaskId = widget.task?.id ?? '';
    if (savedVersion != widget.release.version ||
        savedPath.isEmpty ||
        savedTaskId.isEmpty ||
        (currentTaskId.isNotEmpty && savedTaskId != currentTaskId)) {
      return;
    }
    final file = File(savedPath);
    if (!file.existsSync()) {
      await _clearPendingInstallerState();
      return;
    }
    if (!mounted) return;
    setState(() {
      _downloadedFilePath = savedPath;
      _isInstallerPending = true;
      _currentStatus = 'التحديث تم تنزيله مسبقًا. اضغط "فتح شاشة التثبيت".';
    });
  }

  Future<void> _savePendingInstallerState(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInstallPathKey, filePath);
    await prefs.setString(_pendingInstallVersionKey, widget.release.version);
    await prefs.setString(_pendingInstallTaskIdKey, widget.task?.id ?? '');
  }

  Future<void> _clearPendingInstallerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingInstallPathKey);
    await prefs.remove(_pendingInstallVersionKey);
    await prefs.remove(_pendingInstallTaskIdKey);
  }
}
