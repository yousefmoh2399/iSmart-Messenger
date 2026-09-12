import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/user_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            fullName: _fullNameController.text.trim(),
            password: _passwordController.text.trim(),
          );
      if (!mounted) {
        return;
      }
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الملف الشخصي بنجاح')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    setState(() => _uploadingAvatar = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final filePath = result?.files.single.path;
      if (filePath == null || filePath.isEmpty) {
        return;
      }

      await ref.read(authControllerProvider.notifier).uploadAvatar(filePath);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث الصورة الشخصية')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _pickScanSaveDirectory() async {
    try {
      final selectedPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختر مجلد حفظ ملفات المسح',
      );
      if (selectedPath == null || selectedPath.trim().isEmpty || !mounted) {
        return;
      }
      await ref
          .read(userPreferencesControllerProvider.notifier)
          .setScanSaveDirectoryPath(selectedPath.trim());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث مسار حفظ ملفات المسح')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _pickLocalStorageDirectory() async {
    try {
      final current = ref
          .read(userPreferencesControllerProvider)
          .valueOrNull
          ?.localStorageDirectoryPath;
      final selectedPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختر مجلد تخزين الصور والمرفقات والمستندات',
        initialDirectory: current,
      );
      if (selectedPath == null || selectedPath.trim().isEmpty || !mounted) {
        return;
      }
      await ref
          .read(userPreferencesControllerProvider.notifier)
          .setLocalStorageDirectoryPath(selectedPath.trim());
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('إعادة تشغيل التطبيق'),
          content: const Text(
            'تم تحديث مجلد التخزين. أعد تشغيل التطبيق الآن حتى تقرأ كل شاشات الشات من المسار الجديد.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('تمام'),
            ),
          ],
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث مجلد تخزين ملفات التطبيق')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final userPreferencesState = ref.watch(userPreferencesControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي'), centerTitle: false),
      body: authState.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ShimmerSkeleton(height: 120, borderRadius: 28),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: ShimmerSkeleton(height: 220, borderRadius: 14)),
                SizedBox(width: 10),
                Expanded(child: ShimmerSkeleton(height: 220, borderRadius: 14)),
              ],
            ),
            SizedBox(height: 16),
            ShimmerSkeleton(height: 246, borderRadius: 14),
          ],
        ),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('لا توجد بيانات للمستخدم'));
          }

          if (_fullNameController.text.isEmpty) {
            _fullNameController.text = user.fullName;
          }

          final preferences =
              userPreferencesState.valueOrNull ?? UserPreferences.defaults();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileHero(
                user: user,
                uploadingAvatar: _uploadingAvatar,
                onPickAvatar: _pickAvatar,
              ),
              const SizedBox(height: 16),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تحديث البيانات',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _fullNameController,
                          decoration: const InputDecoration(
                            labelText: 'الاسم الكامل',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length < 2) {
                              return 'الاسم الكامل مطلوب';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: user.username,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'اسم المستخدم',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'كلمة مرور جديدة',
                            hintText: 'اتركها فارغة إذا كنت لا تريد تغييرها',
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _saving ? null : _saveProfile,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            _saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إعدادات الاستخدام',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: preferences.enterSendsMessage,
                        onChanged: (value) => ref
                            .read(userPreferencesControllerProvider.notifier)
                            .setEnterSendsMessage(value),
                        title: const Text('زر Enter يرسل الرسالة'),
                        subtitle: const Text(
                          'لو أغلقتها، Enter ينزل سطر جديد والإرسال من زر الإرسال فقط.',
                        ),
                      ),
                      const Divider(height: 24),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: preferences.autoSaveAfterScan,
                        onChanged: (value) => ref
                            .read(userPreferencesControllerProvider.notifier)
                            .setAutoSaveAfterScan(value),
                        title: const Text('حفظ تلقائي باسم افتراضي بعد المسح'),
                        subtitle: const Text(
                          'لو أغلقتها، سيطلب منك إدخال اسم الملف يدويًا عند الحفظ.',
                        ),
                      ),
                      const Divider(height: 24),
                      DropdownButtonFormField<String>(
                        value: preferences.notificationToneId,
                        decoration: const InputDecoration(
                          labelText: 'نغمة الإشعارات',
                        ),
                        items: NotificationTone.values
                            .map(
                              (tone) => DropdownMenuItem(
                                value: tone.id,
                                child: Text(tone.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            ref
                                .read(
                                  userPreferencesControllerProvider.notifier,
                                )
                                .setNotificationTone(value);
                            ref
                                .read(localNotificationServiceProvider)
                                .previewNotificationTone(value);
                            ref
                                .read(pushNotificationServiceProvider)
                                .registerForAuthenticatedUser();
                          }
                        },
                      ),
                      const Divider(height: 24),
                      Text(
                        'مجلد حفظ ملفات المسح (PDF)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        preferences.scanSaveDirectoryPath ??
                            'المسار الافتراضي داخل التطبيق',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _pickScanSaveDirectory,
                            icon: const Icon(Icons.folder_open_outlined),
                            label: const Text('اختيار مجلد'),
                          ),
                          OutlinedButton.icon(
                            onPressed: preferences.scanSaveDirectoryPath == null
                                ? null
                                : () => ref
                                      .read(
                                        userPreferencesControllerProvider
                                            .notifier,
                                      )
                                      .setScanSaveDirectoryPath(null),
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('إعادة الافتراضي'),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Text(
                        'مجلد تخزين الصور والمرفقات والمستندات',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        preferences.localStorageDirectoryPath ??
                            'iSmart Messenger / Storage داخل مساحة التطبيق',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _pickLocalStorageDirectory,
                            icon: const Icon(Icons.folder_copy_outlined),
                            label: const Text('اختيار مجلد'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                preferences.localStorageDirectoryPath == null
                                ? null
                                : () => ref
                                      .read(
                                        userPreferencesControllerProvider
                                            .notifier,
                                      )
                                      .setLocalStorageDirectoryPath(null),
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('إعادة الافتراضي'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.uploadingAvatar,
    required this.onPickAvatar,
  });

  final AppUser user;
  final bool uploadingAvatar;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (user.presenceStatus) {
      'online' => 'متصل الآن',
      'idle' =>
        user.lastActiveAt == null
            ? 'خامل'
            : 'خامل منذ ${formatEgyptDateTime(user.lastActiveAt!)}',
      _ =>
        user.lastSeen == null
            ? 'غير متصل'
            : 'آخر ظهور ${formatEgyptDateTime(user.lastSeen!)}',
    };

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Center(
          child: Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E5EA),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: user.avatarUrl!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const Center(
                            child: AppLoadingIndicator(size: 24),
                          ),
                          errorWidget: (_, __, ___) => Center(
                            child: Text(
                              user.fullName.isNotEmpty
                                  ? user.fullName.trim().characters.first
                                  : user.username.characters.first,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          user.fullName.isNotEmpty
                              ? user.fullName.trim().characters.first
                              : user.username.characters.first,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
              ),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: GestureDetector(
                  onTap: uploadingAvatar ? null : onPickAvatar,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                        width: 3,
                      ),
                    ),
                    child: uploadingAvatar
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user.fullName.isNotEmpty ? user.fullName : user.username,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          user.role == 'admin' ? 'مسؤول النظام (Admin)' : 'حساب موظف',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
