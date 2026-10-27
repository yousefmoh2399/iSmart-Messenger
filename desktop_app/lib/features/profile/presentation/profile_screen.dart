import 'storage_management_screen.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/settings/user_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;

import '../../../shared/widgets/desktop_workspace_sidebar.dart';
import '../../../shared/widgets/safe_network_avatar.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../updates/presentation/update_center_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.isWrapped = false});

  final bool isWrapped;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _initialized = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _jobTitleController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(
            fullName: _fullNameController.text.trim(),
            jobTitle: _jobTitleController.text.trim(),
            password: _passwordController.text.trim(),
          );
      if (!mounted) return;
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم تحديث الملف الشخصي بنجاح'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(error.toString()),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      final picked = result?.files.single;
      if (picked == null) return;

      Uint8List? initialBytes = picked.bytes;
      if (initialBytes == null && picked.path != null && picked.path!.isNotEmpty) {
        final file = File(picked.path!);
        if (await file.exists()) {
          initialBytes = await file.readAsBytes();
        }
      }

      if (initialBytes == null || initialBytes.isEmpty) {
        throw Exception('تعذر قراءة الصورة المحددة.');
      }

      if (!mounted) return;

      // Show interactive image cropping and adjustment dialog
      final croppedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _AvatarCropDialog(
          imageBytes: initialBytes!,
          fileName: picked.name,
        ),
      );

      if (croppedBytes == null || croppedBytes.isEmpty) {
        return; // User cancelled
      }

      setState(() => _uploadingAvatar = true);

      String? tempFilePath;
      if (!kIsWeb) {
        try {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(
            p.join(tempDir.path, 'cropped_avatar_${DateTime.now().millisecondsSinceEpoch}.png'),
          );
          await tempFile.writeAsBytes(croppedBytes);
          tempFilePath = tempFile.path;
        } catch (_) {}
      }

      await ref.read(authControllerProvider.notifier).uploadAvatar(
            tempFilePath ?? picked.name,
            fileBytes: croppedBytes,
            fileName: 'avatar.png',
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم ضبط وتحديث الصورة الشخصية بنجاح'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(error.toString()),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _pickScanSaveDirectory() async {
    try {
      final selectedPath = kIsWeb && web_bridge.isElectron()
          ? await web_bridge.pickElectronDirectory(
              title: 'اختر مجلد حفظ ملفات المسح',
            )
          : await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'اختر مجلد حفظ ملفات المسح',
            );
      if (selectedPath == null || selectedPath.trim().isEmpty || !mounted) {
        return;
      }
      await ref
          .read(userPreferencesControllerProvider.notifier)
          .setScanSaveDirectoryPath(selectedPath.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم تحديث مسار حفظ ملفات المسح'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(error.toString()),
        ),
      );
    }
  }

  Future<void> _pickLocalStorageDirectory() async {
    try {
      final current = ref
          .read(userPreferencesControllerProvider)
          .valueOrNull
          ?.localStorageDirectoryPath;
      final selectedPath = kIsWeb && web_bridge.isElectron()
          ? await web_bridge.pickElectronDirectory(
              title: 'اختر مجلد تخزين الصور والمرفقات والمستندات',
              defaultPath: current,
            )
          : await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'اختر مجلد تخزين الصور والمرفقات والمستندات',
              initialDirectory: current,
            );
      if (selectedPath == null || selectedPath.trim().isEmpty || !mounted) {
        return;
      }
      await ref
          .read(userPreferencesControllerProvider.notifier)
          .setLocalStorageDirectoryPath(selectedPath.trim());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('إعادة تشغيل التطبيق'),
          content: const Text(
            'تم تحديث مجلد التخزين. أعد تشغيل التطبيق الآن حتى تقرأ كل نوافذ الشات من المسار الجديد.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('تمام'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم تحديث مجلد تخزين ملفات التطبيق'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(error.toString()),
        ),
      );
    }
  }

  void _goToChat() =>
      ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.chat;

  void _goToFiles() =>
      ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.files;

  void _goToServers() =>
      ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.servers;

  void _goToAdminPanel() =>
      ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.admin;

  void _goToTicketsPanel() =>
      ref.read(activeSectionProvider.notifier).state = DesktopWorkspaceSection.tickets;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final userPreferencesState = ref.watch(userPreferencesControllerProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final isDark = themeMode == ThemeMode.dark;
    final user = authState.valueOrNull;
    final canOpenAdmin = user?.canManageChat == true;
    final appServerDefaults = ref.watch(appServerDefaultsProvider).valueOrNull;
    final cachedAppServerDefaults =
        ref.watch(cachedAppServerDefaultsProvider).valueOrNull;
    final showServersShortcut =
        (appServerDefaults ?? cachedAppServerDefaults)?.showServersShortcut ??
            false;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: isDark ? const Color(0xFF0D0D0E) : const Color(0xFFF2F2F7),
                child: authState.when(
                  loading: () => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                        children: const [
                          ShimmerSkeleton(height: 140, borderRadius: 20),
                          SizedBox(height: 20),
                          ShimmerSkeleton(height: 200, borderRadius: 16),
                          SizedBox(height: 20),
                          ShimmerSkeleton(height: 280, borderRadius: 16),
                        ],
                      ),
                    ),
                  ),
                  error: (error, _) => Center(child: Text(error.toString())),
                  data: (user) {
                    if (user == null) {
                      return const Center(
                        child: Text('لا توجد بيانات للمستخدم'),
                      );
                    }

                    if (!_initialized) {
                      _fullNameController.text = user.fullName;
                      _jobTitleController.text = user.jobTitle;
                      _initialized = true;
                    }

                    final preferences =
                        userPreferencesState.valueOrNull ?? UserPreferences.defaults();

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 28,
                          ),
                          children: [
                            // Apple Profile Hero Card
                            _ProfileHero(
                              user: user,
                              uploadingAvatar: _uploadingAvatar,
                              onPickAvatar: _pickAvatar,
                            ),
                            const SizedBox(height: 28),

                            // Basic Information (Read-only)
                            _InsetGroup(
                              title: 'المعلومات الأساسية',
                              children: [
                                _InsetListTile(
                                  icon: Icons.work_rounded,
                                  iconColor: const Color(0xFF007AFF),
                                  title: 'المسمى الوظيفي والفرع',
                                  trailing: Text(
                                    user.jobTitle.isNotEmpty
                                        ? user.jobTitle
                                        : 'غير محدد (يمكنك إضافته بالأسفل)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: user.jobTitle.isNotEmpty
                                          ? (isDark ? Colors.white : const Color(0xFF1C2B3A))
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const Divider(height: 0.5, indent: 52),
                                _InsetListTile(
                                  icon: Icons.badge_rounded,
                                  iconColor: const Color(0xFF34C759),
                                  title: 'الدور والنظام',
                                  trailing: Text(
                                    user.role,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const Divider(height: 0.5, indent: 52),
                                _InsetListTile(
                                  icon: Icons.alternate_email_rounded,
                                  iconColor: const Color(0xFFFF9500),
                                  title: 'اسم المستخدم',
                                  trailing: Text(
                                    user.username,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const Divider(height: 0.5, indent: 52),
                                _InsetListTile(
                                  icon: Icons.admin_panel_settings_rounded,
                                  iconColor: const Color(0xFFAF52DE),
                                  title: 'مستوى الصلاحيات',
                                  trailing: Text(
                                    user.can('canCreateUsers')
                                        ? 'صلاحيات إدارية متقدمة'
                                        : 'صلاحيات مستخدم قياسي',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: user.can('canCreateUsers')
                                          ? const Color(0xFFAF52DE)
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Edit Profile Form
                            Form(
                              key: _formKey,
                              child: _InsetGroup(
                                title: 'تحديث البيانات والفرع',
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    child: TextFormField(
                                      controller: _fullNameController,
                                      style: const TextStyle(fontSize: 14),
                                      decoration: const InputDecoration(
                                        labelText: 'الاسم الكامل',
                                        prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().length < 2) {
                                          return 'الاسم الكامل مطلوب';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const Divider(height: 0.5, indent: 52),

                                  // Job Title + Branch Input Field
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    child: TextFormField(
                                      controller: _jobTitleController,
                                      style: const TextStyle(fontSize: 14),
                                      decoration: const InputDecoration(
                                        labelText: 'المسمى الوظيفي + الفرع',
                                        hintText: 'مثال: محاسب - فرع شبرا أو مسؤول مبيعات - فرع الدقي',
                                        prefixIcon: Icon(Icons.work_outline_rounded, size: 20),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 0.5, indent: 52),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    child: TextFormField(
                                      initialValue: user.username,
                                      enabled: false,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'اسم المستخدم (غير قابل للتعديل)',
                                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 0.5, indent: 52),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    child: TextFormField(
                                      controller: _passwordController,
                                      obscureText: true,
                                      style: const TextStyle(fontSize: 14),
                                      decoration: const InputDecoration(
                                        labelText: 'كلمة مرور جديدة',
                                        hintText: 'اتركها فارغة إذا كنت لا تريد تغييرها',
                                        prefixIcon: Icon(Icons.key_rounded, size: 20),
                                        border: InputBorder.none,
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 0.5),

                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _saving ? null : _saveProfile,
                                        icon: _saving
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(Icons.check_circle_outline_rounded, size: 18),
                                        label: Text(
                                          _saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // App Preferences
                            _InsetGroup(
                              title: 'إعدادات الاستخدام والمحادثة',
                              children: [
                                SwitchListTile.adaptive(
                                  value: preferences.enterSendsMessage,
                                  onChanged: (value) => ref
                                      .read(userPreferencesControllerProvider.notifier)
                                      .setEnterSendsMessage(value),
                                  title: const Text(
                                    'زر Enter يرسل الرسالة',
                                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                  ),
                                  subtitle: const Text(
                                    'إذا تم التعطيل، زر Enter سينشئ سطرًا جديدًا للإرسال يدويًا.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Divider(height: 0.5, indent: 16),
                                SwitchListTile.adaptive(
                                  value: preferences.autoSaveAfterScan,
                                  onChanged: (value) => ref
                                      .read(userPreferencesControllerProvider.notifier)
                                      .setAutoSaveAfterScan(value),
                                  title: const Text(
                                    'حفظ تلقائي باسم افتراضي بعد المسح',
                                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                                  ),
                                  subtitle: const Text(
                                    'إذا تم التعطيل، سيُطلب اسم الملف يدويًا قبل الحفظ.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Divider(height: 0.5, indent: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    value: preferences.notificationToneId,
                                    decoration: const InputDecoration(
                                      labelText: 'نغمة الإشعارات',
                                      prefixIcon: Icon(Icons.notifications_active_outlined, size: 20),
                                      border: InputBorder.none,
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
                                            .read(userPreferencesControllerProvider.notifier)
                                            .setNotificationTone(value);
                                        ref
                                            .read(localNotificationServiceProvider)
                                            .previewNotificationTone(value);
                                      }
                                    },
                                  ),
                                ),
                                const Divider(height: 0.5, indent: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    value: preferences.notificationDisplayModeId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'ظهور الإشعارات على الشاشة',
                                      prefixIcon: Icon(Icons.visibility_outlined, size: 20),
                                      border: InputBorder.none,
                                    ),
                                    selectedItemBuilder: (context) {
                                      return NotificationDisplayMode.values
                                          .map(
                                            (mode) => Text(
                                              mode.label,
                                              style: const TextStyle(fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          )
                                          .toList();
                                    },
                                    items: NotificationDisplayMode.values
                                        .map(
                                          (mode) => DropdownMenuItem(
                                            value: mode.id,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  mode.label,
                                                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                                ),
                                                Text(
                                                  mode.description,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        ref
                                            .read(userPreferencesControllerProvider.notifier)
                                            .setNotificationDisplayMode(value);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // Folders & Paths
                            _InsetGroup(
                              title: 'مسارات الحفظ والتخزين المحلي',
                              children: [
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF34C759).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.picture_as_pdf_rounded,
                                      color: Color(0xFF34C759),
                                      size: 20,
                                    ),
                                  ),
                                  title: const Text(
                                    'مجلد ملفات المسح (PDF)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    preferences.scanSaveDirectoryPath ?? 'المسار الافتراضي',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: FilledButton.tonal(
                                    onPressed: _pickScanSaveDirectory,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('تغيير'),
                                  ),
                                ),
                                 const Divider(height: 0.5, indent: 52),
                                 ListTile(
                                   leading: Container(
                                     width: 36,
                                     height: 36,
                                     decoration: BoxDecoration(
                                       color: const Color(0xFF5856D6).withValues(alpha: 0.14),
                                       borderRadius: BorderRadius.circular(10),
                                     ),
                                     child: const Icon(
                                       Icons.cleaning_services_rounded,
                                       color: Color(0xFF5856D6),
                                       size: 20,
                                     ),
                                   ),
                                   title: const Text(
                                     'إدارة مساحة التخزين والذاكرة المؤقتة (Cache Cleaner)',
                                     style: TextStyle(
                                       fontSize: 14,
                                       fontWeight: FontWeight.w600,
                                     ),
                                   ),
                                   subtitle: Text(
                                     'تفريغ كاش البرنامج ومصغرات الصور والملفات المؤقتة لتسريع الكمبيوتر',
                                     style: TextStyle(
                                       fontSize: 11,
                                       color: Theme.of(context).colorScheme.onSurfaceVariant,
                                     ),
                                   ),
                                   trailing: FilledButton.tonal(
                                     onPressed: () {
                                       Navigator.of(context).push(
                                         MaterialPageRoute(
                                           builder: (_) => const DesktopStorageManagementScreen(),
                                         ),
                                       );
                                     },
                                     style: FilledButton.styleFrom(
                                       padding: const EdgeInsets.symmetric(horizontal: 14),
                                       shape: RoundedRectangleBorder(
                                         borderRadius: BorderRadius.circular(8),
                                       ),
                                     ),
                                     child: const Text('إدارة الذاكرة'),
                                   ),
                                 ),
                                const Divider(height: 0.5, indent: 52),
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF9500).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.folder_rounded,
                                      color: Color(0xFFFF9500),
                                      size: 20,
                                    ),
                                  ),
                                  title: const Text(
                                    'مجلد تخزين الصور والمستندات',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    preferences.localStorageDirectoryPath ?? 'المسار الافتراضي',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: FilledButton.tonal(
                                    onPressed: _pickLocalStorageDirectory,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('تغيير'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (!widget.isWrapped)
              DesktopWorkspaceSidebar(
                user: user,
                activeSection: DesktopWorkspaceSection.profile,
                currentThemeMode: themeMode,
                isDark: isDark,
                accentColor: Theme.of(context).colorScheme.primary,
                onOpenChat: _goToChat,
                onRefresh: () {
                  ref.invalidate(authControllerProvider);
                  ref.invalidate(userPreferencesControllerProvider);
                },
                onOpenFiles: _goToFiles,
                showServersShortcut: showServersShortcut,
                onOpenServers: _goToServers,
                onOpenProfile: () {},
                onOpenUpdates: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UpdateCenterScreen()),
                ),
                onToggleTheme: () =>
                    ref.read(themeModeControllerProvider.notifier).cycleThemeMode(),
                onOpenTickets: _goToTicketsPanel,
                onLogout: () => ref.read(authControllerProvider.notifier).logout(),
                onCreateConversation: _goToChat,
                onOpenAdmin: canOpenAdmin ? _goToAdminPanel : null,
              ),
          ],
        ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final subtitle = switch (user.presenceStatus) {
      'online' => 'متصل الآن',
      'idle' => user.lastActiveAt == null
          ? 'خامل'
          : 'خامل منذ ${formatEgyptDateTime(user.lastActiveAt!)}',
      _ => user.lastSeen == null
          ? 'غير متصل'
          : 'آخر ظهور ${formatEgyptDateTime(user.lastSeen!)}',
    };

    final isOnline = user.presenceStatus == 'online';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
                child: SafeNetworkAvatar(
                  radius: 54,
                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                  imageUrl: user.avatarUrl,
                  fallbackText: user.fullName.isNotEmpty
                      ? user.fullName.trim().characters.first
                      : user.username.characters.first,
                  fallbackTextStyle: theme.textTheme.displaySmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: 2,
                end: 2,
                child: Material(
                  color: cs.primary,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    onTap: uploadingAvatar ? null : onPickAvatar,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
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
              ),
            ],
          ),
          const SizedBox(height: 16),

          // User Full Name
          Text(
            user.fullName.isNotEmpty ? user.fullName : user.username,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),

          // Job Title & Branch Badge
          if (user.jobTitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.work_rounded, size: 14, color: Color(0xFF007AFF)),
                  const SizedBox(width: 6),
                  Text(
                    user.jobTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 6),
          // Presence Status Row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isOnline ? const Color(0xFF34C759) : cs.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsetGroup extends StatelessWidget {
  const _InsetGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              letterSpacing: 0.4,
            ),
          ),
        ),
        Material(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              width: 0.8,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InsetListTile extends StatelessWidget {
  const _InsetListTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _AvatarCropDialog extends StatefulWidget {
  const _AvatarCropDialog({
    required this.imageBytes,
    required this.fileName,
  });

  final Uint8List imageBytes;
  final String fileName;

  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _transformController = TransformationController();
  double _zoomLevel = 1.0;
  int _rotationQuarterTurns = 0;
  bool _isProcessing = false;

  void _onSliderZoomChanged(double value) {
    setState(() {
      _zoomLevel = value;
      final matrix = _transformController.value.clone();
      final currentScale = matrix.getMaxScaleOnAxis();
      final factor = value / currentScale;
      matrix.scale(factor, factor);
      _transformController.value = matrix;
    });
  }

  void _rotate() {
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
  }

  void _reset() {
    setState(() {
      _zoomLevel = 1.0;
      _rotationQuarterTurns = 0;
      _transformController.value = Matrix4.identity();
    });
  }

  Future<void> _confirmCrop() async {
    setState(() => _isProcessing = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('تعذر معالجة إطار الصورة.');
      }
      final uiImage = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null || pngBytes.isEmpty) {
        throw Exception('تعذر تصدير بيانات الصورة المقصوصة.');
      }
      if (!mounted) return;
      Navigator.of(context).pop(pngBytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('حدث خطأ أثناء قص الصورة: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.crop_rounded, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تعديل وقص الصورة الشخصية',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'اسحب وقرّب الصورة لتناسب الإطار الدائري',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Circular Crop Viewport
              Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: Container(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        child: InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 0.5,
                          maxScale: 4.0,
                          boundaryMargin: const EdgeInsets.all(180),
                          clipBehavior: Clip.none,
                          onInteractionUpdate: (details) {
                            final scale = _transformController.value.getMaxScaleOnAxis();
                            if ((scale - _zoomLevel).abs() > 0.05) {
                              setState(() => _zoomLevel = scale.clamp(0.5, 4.0));
                            }
                          },
                          child: Center(
                            child: RotatedBox(
                              quarterTurns: _rotationQuarterTurns,
                              child: Image.memory(
                                widget.imageBytes,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Zoom controls
              Row(
                children: [
                  Icon(Icons.zoom_out_rounded, size: 18, color: cs.onSurfaceVariant),
                  Expanded(
                    child: Slider(
                      value: _zoomLevel.clamp(0.5, 4.0),
                      min: 0.5,
                      max: 4.0,
                      onChanged: _onSliderZoomChanged,
                    ),
                  ),
                  Icon(Icons.zoom_in_rounded, size: 18, color: cs.onSurfaceVariant),
                ],
              ),

              // Action buttons (Rotate, Reset)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _rotate,
                    icon: const Icon(Icons.rotate_90_degrees_cw_rounded, size: 16),
                    label: const Text('تدوير 90°', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('إعادة ضبط', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Confirmation / Cancel
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : _confirmCrop,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(_isProcessing ? 'جارٍ المعالجة...' : 'اعتماد الصورة'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
