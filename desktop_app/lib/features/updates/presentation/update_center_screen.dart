import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../features/admin/models/update_management_models.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/desktop_update_state.dart';

class UpdateCenterScreen extends ConsumerStatefulWidget {
  const UpdateCenterScreen({super.key});

  @override
  ConsumerState<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends ConsumerState<UpdateCenterScreen> {
  late final bool _previousChatSectionVisible;
  PackageInfo? _packageInfo;
  bool _isChecking = false;
  String? _statusMessage;
  DeviceHeartbeatResponse? _lastResponse;
  DesktopUpdateState? _localState;

  @override
  void initState() {
    super.initState();
    _previousChatSectionVisible = ref.read(chatSectionVisibleProvider);
    ref.read(chatSectionVisibleProvider.notifier).state = false;
    _loadPackageInfo();
    _lastResponse = ref.read(desktopUpdateAgentProvider).lastHeartbeatResponse;
    _loadLocalState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    setState(() => _packageInfo = info);
  }

  Future<void> _loadLocalState() async {
    final state = await ref.read(desktopUpdateAgentProvider).loadState();
    if (!mounted) {
      return;
    }
    setState(() => _localState = state);
  }

  Future<void> _checkNow() async {
    final agent = ref.read(desktopUpdateAgentProvider);
    setState(() {
      _isChecking = true;
      _statusMessage = null;
    });
    try {
      final response = await agent.checkNowDetailed();
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResponse = response;
        if (response == null) {
          _statusMessage = 'تعذر قراءة حالة التحديث الحالية.';
        } else if (_localState?.status == 'failed') {
          _statusMessage =
              'آخر محاولة فشلت محليًا. يمكنك إعادة المحاولة من الزر بالأسفل.';
        } else if (_localState?.status == 'downloaded') {
          _statusMessage =
              'التحديث جاهز على هذا الجهاز. أعد تشغيل التطبيق عندما يناسبك.';
        } else if (response.pendingTasks.isEmpty) {
          _statusMessage = 'لا يوجد تحديث مخصص لهذا الجهاز الآن.';
        } else {
          final task = response.pendingTasks.first;
          _statusMessage =
              'تم العثور على تحديث ${task.release.version} وبدأ التنفيذ التلقائي.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.toString();
      });
    } finally {
      await _loadLocalState();
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final agent = ref.read(desktopUpdateAgentProvider);
    final packageInfo = _packageInfo;
    final localState = _localState;
    final currentTask = _lastResponse?.pendingTasks.isNotEmpty == true
        ? _lastResponse!.pendingTasks.first
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('التحديثات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            title: 'الإصدار الحالي',
            lines: [
              'الإصدار: ${packageInfo?.version ?? 'جارٍ التحميل...'}',
              'البيلد: ${packageInfo?.buildNumber ?? '-'}',
              'الفرع: ${user?.branchCode ?? '-'}',
              'معرّف الجهاز: ${agent.deviceUid ?? '-'}',
            ],
          ),
          const SizedBox(height: 12),
          _InfoCard(
            title: 'آخر حالة معروفة',
            lines: [
              if (currentTask != null) ...[
                'الإصدار المستهدف: ${currentTask.release.version}',
                'الحالة: ${_taskStatusLabel(currentTask.status)}',
                'التقدم: ${currentTask.progress}%',
                'نوع المثبت: ${currentTask.release.installerKind}',
              ] else if (localState != null) ...[
                'الحالة المحلية: ${_taskStatusLabel(localState.status)}',
                if ((localState.targetVersion ?? '').isNotEmpty)
                  'الإصدار المستهدف: ${localState.targetVersion}',
                if ((localState.lastError ?? '').isNotEmpty)
                  'سبب الفشل: ${localState.lastError}',
              ] else
                'لا توجد مهمة تحديث نشطة على هذا الجهاز حاليًا.',
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isChecking ? null : _checkNow,
            icon: _isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.system_update_alt_rounded),
            label: Text(_isChecking ? 'جارٍ الفحص...' : 'فحص التحديثات الآن'),
          ),
          if (localState?.status == 'downloaded') ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await ref
                      .read(desktopUpdateAgentProvider)
                      .restartToApplyPreparedUpdate();
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  setState(() => _statusMessage = error.toString());
                }
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('إعادة التشغيل لتثبيت التحديث'),
            ),
          ],
          if (localState?.status == 'failed') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await ref
                      .read(desktopUpdateAgentProvider)
                      .retryFailedUpdate();
                  await _loadLocalState();
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  setState(() => _statusMessage = error.toString());
                }
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
          const SizedBox(height: 12),
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Text(_statusMessage!),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line),
            ),
        ],
      ),
    );
  }
}

String _taskStatusLabel(String status) {
  return switch (status.trim().toLowerCase()) {
    'pending' => 'بانتظار البدء',
    'acknowledged' => 'تم استلام المهمة',
    'downloading' => 'جارٍ التنزيل',
    'installing' => 'جارٍ التثبيت',
    'completed' => 'اكتمل',
    'failed' => 'فشل',
    'cancelled' => 'تم الإلغاء',
    _ => status,
  };
}
