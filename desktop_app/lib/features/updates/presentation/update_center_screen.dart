import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../features/admin/models/update_management_models.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/desktop_update_agent.dart'
    if (dart.library.html) '../../../shared/services/desktop_update_agent_web.dart';
import '../../../shared/services/desktop_update_state.dart';

class UpdateCenterScreen extends ConsumerStatefulWidget {
  const UpdateCenterScreen({super.key});

  @override
  ConsumerState<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends ConsumerState<UpdateCenterScreen> {
  PackageInfo? _packageInfo;
  bool _isChecking = false;
  String? _statusMessage;
  DeviceHeartbeatResponse? _lastResponse;
  DesktopUpdateState? _localState;
  StreamSubscription<DesktopUpdateEvent>? _eventsSub;

  @override
  void initState() {
    super.initState();
    ref.read(chatSectionVisibleProvider.notifier).state = false;
    _loadPackageInfo();
    final agent = ref.read(desktopUpdateAgentProvider);
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user != null && agent.currentUser == null) {
      agent.attachUser(user);
    }
    _lastResponse = agent.lastHeartbeatResponse;
    _loadLocalState();

    _eventsSub = agent.events.listen((event) {
      if (!mounted) return;
      _loadLocalState();
      setState(() {
        if (event.type == 'ready_to_restart') {
          _statusMessage = 'اكتمل تنزيل التحديث وهو جاهز للتثبيت الفوري.';
        } else if (event.type == 'failed') {
          _statusMessage = event.message;
        } else if (event.type == 'heartbeat_error' && _lastResponse == null) {
          _statusMessage = event.message;
        }
      });
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _packageInfo = info);
  }

  Future<void> _loadLocalState() async {
    final state = await ref.read(desktopUpdateAgentProvider).loadState();
    if (!mounted) return;
    setState(() => _localState = state);
  }

  Future<void> _checkNow() async {
    final agent = ref.read(desktopUpdateAgentProvider);
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user != null && agent.currentUser == null) {
      agent.attachUser(user);
    }
    setState(() {
      _isChecking = true;
      _statusMessage = null;
    });
    try {
      final response = await agent.checkNowDetailed();
      if (!mounted) return;
      final currentVersion = _packageInfo?.version ?? '1.1.2';
      setState(() {
        _lastResponse = response;
        if (response == null) {
          _statusMessage = 'تعذر الاتصال بمركز التحديثات.';
        } else if (_localState?.status == 'downloaded') {
          _statusMessage = 'التحديث جاهز للتثبيت على هذا الجهاز.';
        } else if (response.pendingTasks.isEmpty && response.latestRelease == null) {
          _statusMessage = 'أنت تستخدم بالفعل أحدث إصدار معتمد (' + currentVersion + ').';
        } else if (response.latestRelease != null) {
          final isNewer = response.latestRelease!.version.trim().toLowerCase() != currentVersion.trim().toLowerCase();
          if (isNewer) {
            _statusMessage = 'يوجد إصدار جديد معتمد متاح للتحميل (' + response.latestRelease!.version + ').';
          } else {
            _statusMessage = 'أنت تستخدم بالفعل أحدث إصدار معتمد (' + currentVersion + ').';
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      String friendlyError = 'تعذر الاتصال بمركز التحديثات.';
      if (error is DioException) {
        if (error.response?.statusCode == 401) {
          friendlyError = 'انتهت صلاحية الجلسة. برجاء إعادة تسجيل الدخول.';
        } else if (error.response?.statusCode == 429) {
          friendlyError = 'طلبات التحديث كثيرة جدًا. برجاء الانتظار قليلاً ثم المحاولة.';
        } else if (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionError) {
          friendlyError = 'تعذر الاتصال بالخادم. يرجى التحقق من اتصال الشبكة.';
        } else {
          final serverMsg = error.response?.data is Map
              ? (error.response?.data['message'] ?? error.response?.data['error'])?.toString()
              : null;
          friendlyError = serverMsg ?? 'خطأ في الاتصال بالخادم (' + (error.response?.statusCode?.toString() ?? 'شبكة') + ').';
        }
      } else {
        friendlyError = 'تعذر فحص التحديثات: ' + error.toString();
      }
      setState(() => _statusMessage = friendlyError);
    } finally {
      await _loadLocalState();
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final agent = ref.read(desktopUpdateAgentProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    final currentVersion = _packageInfo?.version ?? '1.1.2';
    final currentTask = _lastResponse?.pendingTasks.isNotEmpty == true
        ? _lastResponse!.pendingTasks.first
        : null;
    final latestRelease = _lastResponse?.latestRelease ?? currentTask?.release;

    final hasPreparedUpdate = _localState?.status == 'downloaded';
    final isFailed = _localState?.status == 'failed';

    final isNewerAvailable = latestRelease != null &&
        latestRelease.version.trim().toLowerCase() != currentVersion.trim().toLowerCase();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: const Text(
            'مركز تحديثات المنظومة',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextButton.icon(
                onPressed: _isChecking ? null : _checkNow,
                icon: _isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Iconsax.refresh, size: 18),
                label: Text(_isChecking ? 'جارٍ الفحص...' : 'فحص التحديثات'),
              ),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              children: [
                // Live download progress notifier listener
                ValueListenableBuilder<double?>(
                  valueListenable: agent.downloadProgressNotifier,
                  builder: (context, progress, _) {
                    final isDownloading = progress != null || _localState?.status == 'downloading';
                    return _buildHeroStatusCard(
                      context: context,
                      isDark: isDark,
                      primaryColor: primaryColor,
                      currentVersion: currentVersion,
                      latestRelease: latestRelease,
                      currentTask: currentTask,
                      hasPreparedUpdate: hasPreparedUpdate,
                      isDownloading: isDownloading,
                      downloadProgress: progress ?? 0.0,
                      isFailed: isFailed,
                      isNewerAvailable: isNewerAvailable,
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Changelog / Release Notes Card
                if (latestRelease != null && latestRelease.notes.trim().isNotEmpty) ...[
                  _buildReleaseNotesCard(isDark, latestRelease),
                  const SizedBox(height: 20),
                ],

                // Weak network & Intranet safety features
                _buildIntranetSafeCard(isDark),
                const SizedBox(height: 20),

                // Device & System Diagnostic Details
                _buildDiagnosticsCard(isDark, user, currentVersion, agent),
                const SizedBox(height: 24),

                if (_statusMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Iconsax.info_circle, size: 18, color: primaryColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : const Color(0xFF334155),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroStatusCard({
    required BuildContext context,
    required bool isDark,
    required Color primaryColor,
    required String currentVersion,
    required ManagedUpdateRelease? latestRelease,
    required PendingUpdateTask? currentTask,
    required bool hasPreparedUpdate,
    required bool isDownloading,
    required double downloadProgress,
    required bool isFailed,
    required bool isNewerAvailable,
  }) {
    // 1. Prepared update waiting to be applied
    if (hasPreparedUpdate) {
      final targetVer = _localState?.targetVersion ?? latestRelease?.version ?? 'الجديد';
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'تحديث جاهز للتثبيت الفوري',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'v' + targetVer,
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'تم تنزيل الحزمة محلياً والتحقق من سلامتها (SHA-256). التطبيق جاهز للتثبيت ولن يتم استهلاك أي بيانات إنترنت ثانية.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(desktopUpdateAgentProvider).restartToApplyPreparedUpdate();
                    } catch (e) {
                      if (!mounted) return;
                      setState(() => _statusMessage = e.toString());
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 20),
                  label: const Text(
                    'تثبيت التحديث وإعادة التشغيل الآن',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('المتابعة لاحقاً'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 2. Downloading in background
    if (isDownloading) {
      final percentInt = (downloadProgress * 100).round();
      final targetVersionStr = latestRelease?.version ?? currentTask?.releaseVersion ?? '-';
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Iconsax.document_download, color: primaryColor, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'جارٍ تنزيل التحديث في الخلفية...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'التحميل يتم بهدوء دون التأثير على عملك. يمكنك استخدام الشات والملفات بحرية.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  percentInt.toString() + '%',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: primaryColor,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: downloadProgress > 0 ? downloadProgress : null,
                minHeight: 10,
                backgroundColor: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'يدعم استئناف التحميل في حال ضعف الشبكة (Auto-Resuming)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                  ),
                ),
                Text(
                  'الإصدار المستهدف: ' + targetVersionStr,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 3. Update Available to download
    if (isNewerAvailable && latestRelease != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: primaryColor.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Iconsax.arrow_up_3, color: primaryColor, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'يتوفر إصدار جديد للمنظومة',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'v' + latestRelease.version,
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'إصدار جديد معتمد متاح للتحميل. الإصدار الحالي لديك: ' + currentVersion + '.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      final agent = ref.read(desktopUpdateAgentProvider);
                      if (user != null && agent.currentUser == null) {
                        agent.attachUser(user);
                      }
                      await agent.downloadRelease(latestRelease);
                    } catch (e) {
                      if (!mounted) return;
                      setState(() => _statusMessage = e.toString());
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Iconsax.direct_down, size: 20),
                  label: const Text(
                    'تنزيل التحديث في الخلفية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 4. Failed update state
    if (isFailed) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.red.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تعذر إكمال التحديث الأخير',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _localState?.lastError ?? 'حدث خطأ أثناء تنزيل أو معالجة التحديث.',
                        style: const TextStyle(fontSize: 13, color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await ref.read(desktopUpdateAgentProvider).retryFailedUpdate();
                  await _loadLocalState();
                } catch (e) {
                  if (!mounted) return;
                  setState(() => _statusMessage = e.toString());
                }
              },
              icon: const Icon(Iconsax.refresh, size: 18),
              label: const Text('إعادة المحاولة الآن'),
            ),
          ],
        ),
      );
    }

    // 5. Default: Up to date
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: Color(0xFF10B981),
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'نظامك محدّث بالكامل',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'v' + currentVersion,
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'أنت تستخدم أحدث إصدار معتمد من منظومة iSmart Messenger.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseNotesCard(bool isDark, ManagedUpdateRelease release) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.note_2, size: 20, color: Color(0xFF38BDF8)),
              const SizedBox(width: 10),
              Text(
                'ما الجديد في الإصدار ' + release.version,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            release.notes.trim(),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntranetSafeCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.6)
            : const Color(0xFFF1F5F9).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.shield_tick, size: 18, color: Color(0xFF10B981)),
              const SizedBox(width: 10),
              const Text(
                'ميزات التحميل الآمن والمخصص للشبكة الداخلية (LAN/Intranet)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bulletPoint(
            isDark,
            'استئناف التحميل تلقائياً (Chunked Resumption): في حال انقطاع الشبكة أو ضعف الإشارة، يستكمل التحميل من حيث توقف دون إعادة من الصفر.',
          ),
          _bulletPoint(
            isDark,
            'التدفق بدون استهلاك الذاكرة (Direct Stream-to-Disk): الحزمة تُحفظ مباشرة على القرص دون التأثير على ذاكرة أو أداء الجهاز.',
          ),
          _bulletPoint(
            isDark,
            'التحقق المزدوج من التجزئة الرقمية SHA-256: يتم مطابقة سلامة الملف رقمياً قبل التثبيت لضمان عدم تلفه أثناء الإرسال.',
          ),
        ],
      ),
    );
  }

  Widget _bulletPoint(bool isDark, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard(
    bool isDark,
    dynamic user,
    String currentVersion,
    DesktopUpdateAgent agent,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.setting_4, size: 18, color: Color(0xFF94A3B8)),
              const SizedBox(width: 10),
              const Text(
                'معلومات الجهاز والنظام',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _diagRow(isDark, 'الإصدار المثبت:', currentVersion, isLtr: true),
          _diagRow(isDark, 'الفرع المسجل:', user?.branchCode ?? 'main'),
          _diagRow(isDark, 'معرّف الجهاز (Device UID):', agent.deviceUid ?? '-', isLtr: true),
          _diagRow(isDark, 'حالة الاتصال بالخادم:', 'متصل بالشبكة الداخلية (Online)'),
        ],
      ),
    );
  }

  Widget _diagRow(bool isDark, String label, String value, {bool isLtr = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            textDirection: isLtr ? TextDirection.ltr : null,
          ),
        ],
      ),
    );
  }
}
