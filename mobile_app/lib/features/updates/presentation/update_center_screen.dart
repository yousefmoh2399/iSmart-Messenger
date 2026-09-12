import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/update_models.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/mobile_update_agent.dart';
import '../../../shared/widgets/update_dialog.dart';

class UpdateCenterScreen extends ConsumerStatefulWidget {
  const UpdateCenterScreen({super.key});

  @override
  ConsumerState<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends ConsumerState<UpdateCenterScreen> {
  PackageInfo? _packageInfo;
  String? _deviceUid;
  MobileUpdateCheckResponse? _lastResponse;
  bool _isChecking = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(MobileUpdateAgent.deviceUidStorageKey);
    final deviceUid = (existing != null && existing.trim().isNotEmpty)
        ? existing.trim()
        : const Uuid().v4();
    if (existing == null || existing.trim().isEmpty) {
      await prefs.setString(MobileUpdateAgent.deviceUidStorageKey, deviceUid);
    }
    final info = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceUid = deviceUid;
      _packageInfo = info;
    });
  }

  Future<void> _checkForUpdates() async {
    final user = ref.read(authControllerProvider).valueOrNull;
    final deviceUid = _deviceUid;
    final packageInfo = _packageInfo;
    if (user == null || deviceUid == null || packageInfo == null) {
      return;
    }

    setState(() {
      _isChecking = true;
      _statusMessage = null;
    });
    try {
      final service = ref.read(updateCheckServiceProvider);
      final response = await service.checkForUpdates(
        deviceUid: deviceUid,
        currentVersion: packageInfo.version,
        branchCode: user.branchCode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastResponse = response;
        _statusMessage =
            response.requiresUpdate && response.availableRelease != null
            ? 'تم العثور على إصدار ${response.availableRelease!.version}.'
            : 'أنت على آخر إصدار متاح حاليًا.';
      });
      if (response.requiresUpdate && response.availableRelease != null) {
        await UpdateDialog.show(
          context,
          release: response.availableRelease!,
          task: response.currentTask,
          deviceUid: deviceUid,
          isMandatory: response.isMandatory,
          onUpdate: () {
            if (!mounted) {
              return;
            }
            setState(() {
              _statusMessage = 'تم تحديث التطبيق بنجاح.';
            });
          },
          onLater: response.isMandatory
              ? null
              : () => Navigator.of(context).pop(false),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final packageInfo = _packageInfo;
    final user = ref.watch(authControllerProvider).valueOrNull;
    final release = _lastResponse?.availableRelease;

    return Scaffold(
      appBar: AppBar(title: const Text('التحديثات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _UpdateInfoCard(
            title: 'نسخة التطبيق',
            lines: [
              'الإصدار: ${packageInfo?.version ?? 'جارٍ التحميل...'}',
              'البيلد: ${packageInfo?.buildNumber ?? '-'}',
              'الفرع: ${user?.branchCode ?? '-'}',
              'معرّف الجهاز: ${_deviceUid ?? '-'}',
            ],
          ),
          const SizedBox(height: 12),
          _UpdateInfoCard(
            title: 'آخر نتيجة فحص',
            lines: [
              if (release != null) ...[
                'الإصدار المتاح: ${release.version}',
                'القناة: ${release.channel}',
                'إجباري: ${_lastResponse?.isMandatory == true ? 'نعم' : 'لا'}',
              ] else
                'لم يتم العثور على تحديث بعد.',
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isChecking ? null : _checkForUpdates,
            icon: _isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.system_update_alt_rounded),
            label: Text(_isChecking ? 'جارٍ الفحص...' : 'فحص التحديثات الآن'),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Text(_statusMessage!),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdateInfoCard extends StatelessWidget {
  const _UpdateInfoCard({required this.title, required this.lines});

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
