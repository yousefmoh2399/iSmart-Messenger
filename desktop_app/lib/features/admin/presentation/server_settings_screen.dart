import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../shared/models/app_server_defaults.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';

class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  ConsumerState<ServerSettingsScreen> createState() =>
      _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final TextEditingController _desktopBaseUrlController =
      TextEditingController();
  final TextEditingController _mobileBaseUrlController =
      TextEditingController();
  final TextEditingController _snipeitUrlController = TextEditingController();
  final List<_EditableServerTarget> _targets = <_EditableServerTarget>[];
  bool _showServersShortcut = true;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  @override
  void dispose() {
    _desktopBaseUrlController.dispose();
    _mobileBaseUrlController.dispose();
    _snipeitUrlController.dispose();
    for (final target in _targets) {
      target.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final defaults = await ref
          .read(publicAppSettingsServiceProvider)
          .fetchDefaults();
      _desktopBaseUrlController.text = defaults.desktopBaseUrl ?? '';
      _mobileBaseUrlController.text = defaults.mobileBaseUrl ?? '';
      _snipeitUrlController.text = defaults.snipeitUrl ?? '';
      _showServersShortcut = defaults.showServersShortcut;
      for (final target in _targets) {
        target.dispose();
      }
      _targets
        ..clear()
        ..addAll(defaults.serverTargets.map(_EditableServerTarget.fromModel));
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _addTarget() {
    setState(() {
      _targets.add(_EditableServerTarget.empty());
    });
  }

  void _removeTarget(_EditableServerTarget target) {
    setState(() {
      _targets.remove(target);
      target.dispose();
    });
  }

  List<AppServerTarget> _normalizedTargets() {
    return _targets
        .map((target) => target.toModel())
        .whereType<AppServerTarget>()
        .toList();
  }

  Future<void> _saveDefaults() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final token = await ref.read(authRepositoryProvider).getToken();
      if (token == null || token.trim().isEmpty) {
        throw StateError('Missing authentication token.');
      }
      final saved = await ref
          .read(appSettingsServiceProvider)
          .updateDefaults(
            token: token,
            desktopBaseUrl: _desktopBaseUrlController.text.trim(),
            mobileBaseUrl: _mobileBaseUrlController.text.trim(),
            snipeitUrl: _snipeitUrlController.text.trim(),
            serverTargets: _normalizedTargets(),
            showServersShortcut: _showServersShortcut,
          );
      if (mounted) {
        _desktopBaseUrlController.text = saved.desktopBaseUrl ?? '';
        _mobileBaseUrlController.text = saved.mobileBaseUrl ?? '';
        _snipeitUrlController.text = saved.snipeitUrl ?? '';
        _showServersShortcut = saved.showServersShortcut;
        ref.read(appSettingsRevisionProvider.notifier).state++;
        _showSnack('تم حفظ إعدادات الخادم.');
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'إعدادات الخادم',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'يمكنك تحديد رابط الـ API الافتراضي وقائمة السيرفرات والبورتات المستخدمة في صفحة السيرفرات بدون إعادة تثبيت البرنامج.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_loading)
                const LinearProgressIndicator(minHeight: 2)
              else
                Expanded(
                  child: ListView(
                    children: [
                      TextField(
                        controller: _desktopBaseUrlController,
                        decoration: const InputDecoration(
                          labelText: 'رابط API الافتراضي للديسكتوب',
                          hintText: 'https://api.example.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _mobileBaseUrlController,
                        decoration: const InputDecoration(
                          labelText: 'رابط API الافتراضي للموبايل',
                          hintText: 'https://api.example.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _snipeitUrlController,
                        decoration: const InputDecoration(
                          labelText: 'رابط Snipe-IT',
                          hintText: 'https://snipeit.example.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showServersShortcut,
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() {
                                  _showServersShortcut = value;
                                });
                              },
                        title: const Text('إظهار أيقونة السيرفرات'),
                        subtitle: const Text(
                          'عند إيقافها تختفي أيقونة السيرفرات فقط من شريط الديسكتوب.',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Text(
                            'السيرفرات الظاهرة في صفحة السيرفرات',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Spacer(),
                          FilledButton.tonalIcon(
                            onPressed: _saving ? null : _addTarget,
                            icon: const Icon(Iconsax.add),
                            label: const Text('إضافة سيرفر'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_targets.isEmpty)
                        const Text('لا توجد سيرفرات محفوظة حالياً.')
                      else
                        ..._targets.map(
                          (target) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ServerTargetCard(
                              target: target,
                              saving: _saving,
                              onRemove: () => _removeTarget(target),
                            ),
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _loading || _saving ? null : _saveDefaults,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: ButtonLoadingIndicator(),
                        )
                      : const Icon(Iconsax.save_2),
                  label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerTargetCard extends StatelessWidget {
  const _ServerTargetCard({
    required this.target,
    required this.saving,
    required this.onRemove,
  });

  final _EditableServerTarget target;
  final bool saving;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: target.titleController,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'اسم السيرفر',
                      hintText: 'Archive SVR',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: saving ? null : onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: target.baseUrlController,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'الرابط الأساسي',
                hintText: 'http://192.168.1.10:9090/',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: target.portsController,
              enabled: !saving,
              decoration: const InputDecoration(
                labelText: 'البورتات المتاحة',
                hintText: '9090, 7003, 7005',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableServerTarget {
  _EditableServerTarget({
    required String title,
    required String baseUrl,
    required String ports,
  }) : titleController = TextEditingController(text: title),
       baseUrlController = TextEditingController(text: baseUrl),
       portsController = TextEditingController(text: ports);

  factory _EditableServerTarget.empty() =>
      _EditableServerTarget(title: '', baseUrl: '', ports: '');

  factory _EditableServerTarget.fromModel(AppServerTarget target) =>
      _EditableServerTarget(
        title: target.title,
        baseUrl: target.baseUrl,
        ports: target.ports.join(', '),
      );

  final TextEditingController titleController;
  final TextEditingController baseUrlController;
  final TextEditingController portsController;

  AppServerTarget? toModel() {
    final title = titleController.text.trim();
    final baseUrl = baseUrlController.text.trim();
    if (title.isEmpty || baseUrl.isEmpty) {
      return null;
    }
    final ports = portsController.text
        .split(',')
        .map((entry) => int.tryParse(entry.trim()))
        .whereType<int>()
        .where((entry) => entry > 0)
        .toList();
    return AppServerTarget(title: title, baseUrl: baseUrl, ports: ports);
  }

  void dispose() {
    titleController.dispose();
    baseUrlController.dispose();
    portsController.dispose();
  }
}
