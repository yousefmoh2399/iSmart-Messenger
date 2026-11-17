import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  int get _totalConfiguredPorts {
    var count = 0;
    for (final target in _targets) {
      count += target.parsedPorts.length;
    }
    return count;
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
        _showSnack('تم حفظ إعدادات الخادم بنجاح.');
      }
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    Clipboard.setData(ClipboardData(text: trimmed));
    _showSnack('تم نسخ $label');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF0B0F17) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF151C28) : Colors.white;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);
    const accentColor = Color(0xFF007AFF);

    return Container(
      color: pageBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Hero Header
          Container(
            margin: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderCol),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 900;

                    final titleSection = Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accentColor.withValues(alpha: 0.2),
                                accentColor.withValues(alpha: 0.08),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Iconsax.setting_2,
                            color: accentColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'إعدادات الخادم والاتصال المركزي',
                                    style: Theme.of(context).textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontSize: isCompact ? 16 : 18,
                                        ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF34C759,
                                      ).withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 7,
                                          color: Color(0xFF34C759),
                                        ),
                                        SizedBox(width: 5),
                                        Text(
                                          'مزامنة فورية',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF34C759),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'تحكم في روابط الـ API الافتراضية لنسخ الديسكتوب والموبايل ونظام الأصول وقائمة السيرفرات والبورتات دون الحاجة لإعادة تثبيت التطبيق.',
                                style: TextStyle(
                                  fontSize: isCompact ? 11.5 : 12.5,
                                  height: 1.35,
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

                    final actionsSection = Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton.filledTonal(
                          onPressed: _loading || _saving ? null : _loadDefaults,
                          tooltip: 'إعادة تحميل الإعدادات',
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Iconsax.refresh, size: 18),
                        ),
                        FilledButton.icon(
                          onPressed: _loading || _saving ? null : _saveDefaults,
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: ButtonLoadingIndicator(),
                                )
                              : const Icon(Iconsax.tick_circle, size: 18),
                          label: Text(
                            _saving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    );

                    return isCompact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleSection,
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerRight,
                                child: actionsSection,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: titleSection),
                              const SizedBox(width: 14),
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: actionsSection,
                                ),
                              ),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 16),
                // Stats strip
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ServerMetricChip(
                      icon: Iconsax.driver,
                      label: 'السيرفرات المضافة',
                      value: '${_targets.length}',
                      color: accentColor,
                      isDark: isDark,
                    ),
                    _ServerMetricChip(
                      icon: Iconsax.hierarchy_square_2,
                      label: 'إجمالي البورتات',
                      value: '$_totalConfiguredPorts',
                      color: const Color(0xFF5856D6),
                      isDark: isDark,
                    ),
                    _ServerMetricChip(
                      icon: Iconsax.eye,
                      label: 'اختصار السيرفرات الجانبي',
                      value: _showServersShortcut ? 'مفعّل' : 'مخفي',
                      color: _showServersShortcut
                          ? const Color(0xFF34C759)
                          : const Color(0xFFFF9500),
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_error != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Iconsax.warning_2,
                    color: Color(0xFFFF3B30),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFF3B30),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_loading)
            const Expanded(
              child: Center(child: CupertinoActivityIndicator(radius: 16)),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  // Section 1: Core API & Asset Endpoints
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Iconsax.global,
                                size: 18,
                                color: accentColor,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'روابط الاتصال الأساسية (Core Endpoints)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'العناوين الافتراضية لتطبيقات سطح المكتب والموبايل ونظام إدارة الأصول',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth > 760;
                            if (wide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _AppleEndpointField(
                                      controller: _desktopBaseUrlController,
                                      label: 'رابط API الافتراضي للديسكتوب',
                                      hint: 'https://api.example.com',
                                      badge: 'Desktop API',
                                      icon: Iconsax.monitor,
                                      accentColor: const Color(0xFF007AFF),
                                      isDark: isDark,
                                      enabled: !_saving,
                                      onCopy: () => _copyToClipboard(
                                        _desktopBaseUrlController.text,
                                        'رابط الديسكتوب',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _AppleEndpointField(
                                      controller: _mobileBaseUrlController,
                                      label: 'رابط API الافتراضي للموبايل',
                                      hint: 'https://api.example.com',
                                      badge: 'Mobile API',
                                      icon: Iconsax.mobile,
                                      accentColor: const Color(0xFF34C759),
                                      isDark: isDark,
                                      enabled: !_saving,
                                      onCopy: () => _copyToClipboard(
                                        _mobileBaseUrlController.text,
                                        'رابط الموبايل',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: _AppleEndpointField(
                                      controller: _snipeitUrlController,
                                      label: 'رابط نظام الأصول Snipe-IT',
                                      hint: 'https://snipeit.example.com',
                                      badge: 'Assets URL',
                                      icon: Iconsax.box,
                                      accentColor: const Color(0xFFFF9500),
                                      isDark: isDark,
                                      enabled: !_saving,
                                      onCopy: () => _copyToClipboard(
                                        _snipeitUrlController.text,
                                        'رابط Snipe-IT',
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                _AppleEndpointField(
                                  controller: _desktopBaseUrlController,
                                  label: 'رابط API الافتراضي للديسكتوب',
                                  hint: 'https://api.example.com',
                                  badge: 'Desktop API',
                                  icon: Iconsax.monitor,
                                  accentColor: const Color(0xFF007AFF),
                                  isDark: isDark,
                                  enabled: !_saving,
                                  onCopy: () => _copyToClipboard(
                                    _desktopBaseUrlController.text,
                                    'رابط الديسكتوب',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _AppleEndpointField(
                                  controller: _mobileBaseUrlController,
                                  label: 'رابط API الافتراضي للموبايل',
                                  hint: 'https://api.example.com',
                                  badge: 'Mobile API',
                                  icon: Iconsax.mobile,
                                  accentColor: const Color(0xFF34C759),
                                  isDark: isDark,
                                  enabled: !_saving,
                                  onCopy: () => _copyToClipboard(
                                    _mobileBaseUrlController.text,
                                    'رابط الموبايل',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _AppleEndpointField(
                                  controller: _snipeitUrlController,
                                  label: 'رابط نظام الأصول Snipe-IT',
                                  hint: 'https://snipeit.example.com',
                                  badge: 'Assets URL',
                                  icon: Iconsax.box,
                                  accentColor: const Color(0xFFFF9500),
                                  isDark: isDark,
                                  enabled: !_saving,
                                  onCopy: () => _copyToClipboard(
                                    _snipeitUrlController.text,
                                    'رابط Snipe-IT',
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        // Shortcut toggle card inside section
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.03)
                                : const Color(0xFFF2F2F7).withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderCol),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: (_showServersShortcut
                                          ? const Color(0xFF34C759)
                                          : Colors.grey)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Iconsax.sidebar_right,
                                  size: 18,
                                  color: _showServersShortcut
                                      ? const Color(0xFF34C759)
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'إظهار أيقونة السيرفرات في الشريط الجانبي',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    Text(
                                      'عند إيقاف هذا الخيار تختفي أيقونة السيرفرات السريعة من الشريط الجانبي لنسخة الديسكتوب.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              CupertinoSwitch(
                                value: _showServersShortcut,
                                activeTrackColor: const Color(0xFF34C759),
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _showServersShortcut = value;
                                        });
                                      },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Section 2: Server Targets & Ports
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF5856D6,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Iconsax.driver,
                                size: 18,
                                color: Color(0xFF5856D6),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'قائمة السيرفرات والبورتات (Server Targets)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF5856D6,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '${_targets.length} سيرفر',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF5856D6),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Text(
                                    'السيرفرات والأنظمة الداخلية التي تظهر للمستخدمين في شاشة السيرفرات مع البورتات المتاحة لكل سيرفر',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _addTarget,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFF5856D6,
                                ).withValues(alpha: 0.12),
                                foregroundColor: const Color(0xFF5856D6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              icon: const Icon(Iconsax.add_circle, size: 18),
                              label: const Text(
                                'إضافة سيرفر جديد',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_targets.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 36,
                              horizontal: 20,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.02)
                                  : const Color(0xFFF2F2F7).withValues(
                                      alpha: 0.5,
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderCol),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Iconsax.driver_refresh,
                                  size: 40,
                                  color: isDark
                                      ? Colors.white30
                                      : Colors.black26,
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'لا توجد سيرفرات مضافة حالياً',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'اضغط على "إضافة سيرفر جديد" لإضافة عنوان سيرفر وبورتات الخدمة الخاصة به.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._targets.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final target = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ServerTargetCard(
                                index: idx + 1,
                                target: target,
                                saving: _saving,
                                isDark: isDark,
                                onChanged: () => setState(() {}),
                                onRemove: () => _removeTarget(target),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ServerMetricChip extends StatelessWidget {
  const _ServerMetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleEndpointField extends StatelessWidget {
  const _AppleEndpointField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.badge,
    required this.icon,
    required this.accentColor,
    required this.isDark,
    required this.enabled,
    required this.onCopy,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String badge;
  final IconData icon;
  final Color accentColor;
  final bool isDark;
  final bool enabled;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFFF2F2F7).withValues(alpha: 0.75);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: enabled,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white30 : Colors.black38,
              ),
              isDense: true,
              filled: true,
              fillColor: isDark ? const Color(0xFF0E141F) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                onPressed: onCopy,
                icon: const Icon(Iconsax.copy, size: 16),
                tooltip: 'نسخ الرابط',
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerTargetCard extends StatelessWidget {
  const _ServerTargetCard({
    required this.index,
    required this.target,
    required this.saving,
    required this.isDark,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _EditableServerTarget target;
  final bool saving;
  final bool isDark;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ports = target.parsedPorts;
    final titleText = target.titleController.text.trim();
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF5856D6).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '#$index',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFF5856D6),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titleText.isEmpty ? 'سيرفر جديد #$index' : titleText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              if (ports.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: ports
                      .take(5)
                      .map(
                        (port) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF007AFF,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            ':$port',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF007AFF),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: saving ? null : onRemove,
                tooltip: 'حذف السيرفر',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(
                    0xFFFF3B30,
                  ).withValues(alpha: 0.1),
                  foregroundColor: const Color(0xFFFF3B30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Iconsax.trash, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 680;
              final nameField = TextField(
                controller: target.titleController,
                enabled: !saving,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: 'اسم السيرفر',
                  hintText: 'مثال: Archive SVR',
                  prefixIcon: const Icon(Iconsax.driver, size: 17),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0E141F) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                ),
              );
              final urlField = TextField(
                controller: target.baseUrlController,
                enabled: !saving,
                onChanged: (_) => onChanged(),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'الرابط الأساسي (Base URL)',
                  hintText: 'http://192.168.1.10:9090/',
                  prefixIcon: const Icon(Iconsax.link, size: 17),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0E141F) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                ),
              );
              final portsField = TextField(
                controller: target.portsController,
                enabled: !saving,
                onChanged: (_) => onChanged(),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'البورتات المتاحة (مفصولة بفاصلة)',
                  hintText: '9090, 7003, 7005',
                  prefixIcon: const Icon(Iconsax.hierarchy_square_2, size: 17),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0E141F) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                ),
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: nameField),
                    const SizedBox(width: 10),
                    Expanded(flex: 4, child: urlField),
                    const SizedBox(width: 10),
                    Expanded(flex: 3, child: portsField),
                  ],
                );
              }
              return Column(
                children: [
                  nameField,
                  const SizedBox(height: 10),
                  urlField,
                  const SizedBox(height: 10),
                  portsField,
                ],
              );
            },
          ),
        ],
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

  List<int> get parsedPorts => portsController.text
      .split(',')
      .map((entry) => int.tryParse(entry.trim()))
      .whereType<int>()
      .where((entry) => entry > 0)
      .toList();

  AppServerTarget? toModel() {
    final title = titleController.text.trim();
    final baseUrl = baseUrlController.text.trim();
    if (title.isEmpty || baseUrl.isEmpty) {
      return null;
    }
    return AppServerTarget(title: title, baseUrl: baseUrl, ports: parsedPorts);
  }

  void dispose() {
    titleController.dispose();
    baseUrlController.dispose();
    portsController.dispose();
  }
}
