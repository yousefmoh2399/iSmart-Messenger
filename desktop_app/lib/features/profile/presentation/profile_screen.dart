import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/user_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;

import '../../../shared/widgets/desktop_workspace_sidebar.dart';
import '../../../shared/widgets/safe_network_avatar.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../chat/presentation/chat_dashboard_screen.dart';
import '../../files/presentation/files_dashboard_screen.dart';
import '../../servers/presentation/servers_screen.dart';
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
        withData: kIsWeb,
      );
      final picked = result?.files.single;
      if (picked == null) {
        return;
      }
      final filePath = picked.path;
      final fileBytes = picked.bytes;
      if (kIsWeb && fileBytes == null) {
        throw Exception('تعذر قراءة الصورة من المتصفح.');
      }
      if (!kIsWeb && (filePath == null || filePath.isEmpty)) {
        return;
      }

      await ref
          .read(authControllerProvider.notifier)
          .uploadAvatar(
            filePath ?? picked.name,
            fileBytes: fileBytes,
            fileName: picked.name,
          );
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
      if (!mounted) {
        return;
      }
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

  void _goToChat() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const ChatDashboardScreen()),
  );

  void _goToFiles() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const FilesDashboardScreen()),
  );

  void _goToServers() => Navigator.of(
    context,
  ).pushReplacement(MaterialPageRoute(builder: (_) => const ServersScreen()));

  void _goToAdminPanel() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => const ChatDashboardScreen(openAdminOnStart: true),
    ),
  );

  void _goToTicketsPanel() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => const ChatDashboardScreen(openTicketsOnStart: true),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final userPreferencesState = ref.watch(userPreferencesControllerProvider);
    final themeMode =
        ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.light;
    final user = authState.valueOrNull;
    final canOpenAdmin = user?.canManageChat == true;
    final appServerDefaults = ref.watch(appServerDefaultsProvider).valueOrNull;
    final cachedAppServerDefaults = ref
        .watch(cachedAppServerDefaultsProvider)
        .valueOrNull;
    final showServersShortcut =
        (appServerDefaults ?? cachedAppServerDefaults)?.showServersShortcut ??
        false;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                color: themeMode == ThemeMode.dark
                    ? Colors.black
                    : const Color(0xFFF2F2F7),
                child: authState.when(
                  loading: () => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: const [
                          ShimmerSkeleton(height: 132, borderRadius: 30),
                          SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: ShimmerSkeleton(
                                  height: 260,
                                  borderRadius: 14,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: ShimmerSkeleton(
                                  height: 260,
                                  borderRadius: 14,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 18),
                          ShimmerSkeleton(height: 286, borderRadius: 14),
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

                    if (_fullNameController.text.isEmpty) {
                      _fullNameController.text = user.fullName;
                    }

                    final preferences =
                        userPreferencesState.valueOrNull ??
                        UserPreferences.defaults();

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            _ProfileHero(
                              user: user,
                              uploadingAvatar: _uploadingAvatar,
                              onPickAvatar: _pickAvatar,
                            ),
                            const SizedBox(height: 32),
                            _InsetGroup(
                              title: 'المعلومات الأساسية',
                              children: [
                                _InsetListTile(
                                  icon: Icons.badge_rounded,
                                  iconColor: Colors.blue,
                                  title: 'الدور',
                                  trailing: Text(
                                    user.role,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                _InsetListTile(
                                  icon: Icons.account_circle_rounded,
                                  iconColor: Colors.orange,
                                  title: 'اسم المستخدم',
                                  trailing: Text(
                                    user.username,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                _InsetListTile(
                                  icon: Icons.admin_panel_settings_rounded,
                                  iconColor: Colors.purple,
                                  title: 'الصلاحيات',
                                  trailing: Text(
                                    user.can('canCreateUsers')
                                        ? 'صلاحيات متقدمة'
                                        : 'صلاحيات أساسية',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Form(
                              key: _formKey,
                              child: _InsetGroup(
                                title: 'تحديث البيانات',
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    child: TextFormField(
                                      controller: _fullNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'الاسم الكامل',
                                        border: InputBorder.none,
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().length < 2) {
                                          return 'الاسم الكامل مطلوب';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const Divider(height: 1, indent: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    child: TextFormField(
                                      initialValue: user.username,
                                      enabled: false,
                                      decoration: const InputDecoration(
                                        labelText: 'اسم المستخدم',
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 1, indent: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    child: TextFormField(
                                      controller: _passwordController,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: 'كلمة مرور جديدة',
                                        hintText:
                                            'اتركها فارغة إذا كنت لا تريد تغييرها',
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 1, indent: 16),
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton(
                                        onPressed: _saving
                                            ? null
                                            : _saveProfile,
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          _saving
                                              ? 'جارٍ الحفظ...'
                                              : 'حفظ التغييرات',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            _InsetGroup(
                              title: 'إعدادات الاستخدام',
                              children: [
                                SwitchListTile.adaptive(
                                  value: preferences.enterSendsMessage,
                                  onChanged: (value) => ref
                                      .read(
                                        userPreferencesControllerProvider
                                            .notifier,
                                      )
                                      .setEnterSendsMessage(value),
                                  title: const Text('زر Enter يرسل الرسالة'),
                                  subtitle: const Text(
                                    'لو أغلقتها، Enter ينزل سطر جديد للإرسال يدويًا.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Divider(height: 1, indent: 16),
                                SwitchListTile.adaptive(
                                  value: preferences.autoSaveAfterScan,
                                  onChanged: (value) => ref
                                      .read(
                                        userPreferencesControllerProvider
                                            .notifier,
                                      )
                                      .setAutoSaveAfterScan(value),
                                  title: const Text(
                                    'حفظ تلقائي باسم افتراضي بعد المسح',
                                  ),
                                  subtitle: const Text(
                                    'لو أغلقتها، سيُطلب اسم الملف يدويًا قبل الحفظ.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Divider(height: 1, indent: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: DropdownButtonFormField<String>(
                                    value: preferences.notificationToneId,
                                    decoration: const InputDecoration(
                                      labelText: 'نغمة الإشعارات',
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
                                            .read(
                                              userPreferencesControllerProvider
                                                  .notifier,
                                            )
                                            .setNotificationTone(value);
                                        ref
                                            .read(
                                              localNotificationServiceProvider,
                                            )
                                            .previewNotificationTone(value);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _InsetGroup(
                              title: 'المجلدات والمقاطع',
                              children: [
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.picture_as_pdf_rounded,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                  ),
                                  title: const Text(
                                    'مجلد ملفات المسح (PDF)',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    preferences.scanSaveDirectoryPath ??
                                        'المسار الافتراضي',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: TextButton(
                                    onPressed: _pickScanSaveDirectory,
                                    child: const Text('تغيير'),
                                  ),
                                ),
                                const Divider(height: 1, indent: 16),
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.folder_rounded,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                  ),
                                  title: const Text(
                                    'مجلد تخزين الصور والمستندات',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Text(
                                    preferences.localStorageDirectoryPath ??
                                        'المسار الافتراضي',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: TextButton(
                                    onPressed: _pickLocalStorageDirectory,
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
                isDark: themeMode == ThemeMode.dark,
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
                onToggleTheme: () => ref
                    .read(themeModeControllerProvider.notifier)
                    .cycleThemeMode(),
                onOpenTickets: _goToTicketsPanel,
                onLogout: () =>
                    ref.read(authControllerProvider.notifier).logout(),
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

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SafeNetworkAvatar(
              radius: 56,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              imageUrl: user.avatarUrl,
              fallbackText: user.fullName.isNotEmpty
                  ? user.fullName.trim().characters.first
                  : user.username.characters.first,
              fallbackTextStyle: Theme.of(context).textTheme.displaySmall
                  ?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            PositionedDirectional(
              bottom: 0,
              end: 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  onTap: uploadingAvatar ? null : onPickAvatar,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: uploadingAvatar
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_rounded, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          user.fullName.isNotEmpty ? user.fullName : user.username,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: isDark
                ? null
                : Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          clipBehavior: Clip.antiAlias,
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
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: trailing,
    );
  }
}
