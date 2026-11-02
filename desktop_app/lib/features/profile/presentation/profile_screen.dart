import 'storage_management_screen.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import '../../chat/presentation/chat_appearance_screen.dart';
import '../../chat/presentation/widgets/desktop_message_actions_dialogs.dart';
import '../../chat/presentation/widgets/desktop_quick_replies.dart';
import '../../chat/presentation/widgets/instant_clipboard_sync_dialog.dart';
import '../../updates/presentation/update_center_screen.dart';
import 'active_sessions_dialog.dart';

enum _DesktopSettingsSection {
  profile(
    title: 'الملف الشخصي والحساب',
    subtitle: 'بياناتك الشخصية، المسمى والفرع، وتغيير كلمة المرور',
    icon: Icons.person_rounded,
    accentColor: Color(0xFF007AFF),
  ),
  appearance(
    title: 'المظهر واستوديو الشات',
    subtitle: 'الوضع الليلي، ثيمات تلجرام، رأس السنة والجليد ❄️، وحماية العين',
    icon: Icons.palette_rounded,
    accentColor: Color(0xFFAF52DE),
  ),
  notifications(
    title: 'الإشعارات والأصوات',
    subtitle: 'نغمات التنبيه المخصصة وأسلوب الظهور على الشاشة',
    icon: Icons.notifications_active_rounded,
    accentColor: Color(0xFFFF9500),
  ),
  storage(
    title: 'التخزين والملفات والذاكرة',
    subtitle: 'مسارات الحفظ وتفريغ الكاش والملفات المؤقتة لتسريع التطبيق',
    icon: Icons.storage_rounded,
    accentColor: Color(0xFF34C759),
  ),
  smartTools(
    title: 'الأدوات الذكية للشات',
    subtitle: 'الحافظة الفورية بين الأجهزة، الردود السريعة (/)، والتذكيرات المجدولة',
    icon: Icons.bolt_rounded,
    accentColor: Color(0xFF5856D6),
  ),
  security(
    title: 'الأجهزة والأمان',
    subtitle: 'الأجهزة المسجل الدخول منها، مستوى الصلاحيات، وتسجيل الخروج',
    icon: Icons.shield_rounded,
    accentColor: Color(0xFFFF2D55),
  );

  const _DesktopSettingsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
}

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
  bool _obscurePassword = true;
  _DesktopSettingsSection _selectedSection = _DesktopSettingsSection.profile;

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

      final croppedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _AvatarCropDialog(
          imageBytes: initialBytes!,
          fileName: picked.name,
        ),
      );

      if (croppedBytes == null || croppedBytes.isEmpty || !mounted) return;

      setState(() => _uploadingAvatar = true);

      final tempDir = await getTemporaryDirectory();
      final tempFilePath = p.join(
        tempDir.path,
        'avatar_cropped_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final tempFile = File(tempFilePath);
      await tempFile.writeAsBytes(croppedBytes, flush: true);

      await ref.read(authControllerProvider.notifier).uploadAvatar(tempFile.path);

      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم تحديث الصورة الشخصية بنجاح'),
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

                    return Row(
                      children: [
                        // ── Left Navigation Sidebar (Apple Control Center Style) ──
                        Container(
                          width: 270,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF161618) : Colors.white,
                            border: Border(
                              left: BorderSide(
                                color: isDark
                                    ? const Color(0xFF2C2C2E)
                                    : const Color(0xFFE5E5EA),
                                width: 0.8,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // User Mini Header
                              _SidebarUserHeader(
                                user: user,
                                isDark: isDark,
                                isSelected: _selectedSection == _DesktopSettingsSection.profile,
                                onTap: () => setState(() => _selectedSection = _DesktopSettingsSection.profile),
                              ),
                              Divider(
                                height: 1,
                                color: isDark ? const Color(0xFF262628) : const Color(0xFFEDEDF2),
                              ),
                              const SizedBox(height: 8),

                              // Category Navigation List
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  children: _DesktopSettingsSection.values.map((section) {
                                    final isSelected = _selectedSection == section;
                                    return _SidebarNavTile(
                                      section: section,
                                      isSelected: isSelected,
                                      isDark: isDark,
                                      onTap: () => setState(() => _selectedSection = section),
                                    );
                                  }).toList(),
                                ),
                              ),

                              // Bottom Sidebar Footer
                              Divider(
                                height: 1,
                                color: isDark ? const Color(0xFF262628) : const Color(0xFFEDEDF2),
                              ),
                              _SidebarFooter(
                                isDark: isDark,
                                onLogout: () => _confirmLogout(context),
                              ),
                            ],
                          ),
                        ),

                        // ── Main Content Area ──
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Top Bar Header
                              _SectionTopHeader(
                                section: _selectedSection,
                                isDark: isDark,
                              ),

                              // Section View Body
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(36, 24, 36, 48),
                                  children: [
                                    Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 780),
                                        child: _buildSectionContent(
                                          user: user,
                                          preferences: preferences,
                                          isDark: isDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 24),
              SizedBox(width: 10),
              Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج من هذا الحساب؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  Widget _buildSectionContent({
    required AppUser user,
    required UserPreferences preferences,
    required bool isDark,
  }) {
    switch (_selectedSection) {
      case _DesktopSettingsSection.profile:
        return _buildProfileContent(user: user, isDark: isDark);
      case _DesktopSettingsSection.appearance:
        return _buildAppearanceContent(preferences: preferences, isDark: isDark);
      case _DesktopSettingsSection.notifications:
        return _buildNotificationsContent(preferences: preferences, isDark: isDark);
      case _DesktopSettingsSection.storage:
        return _buildStorageContent(preferences: preferences, isDark: isDark);
      case _DesktopSettingsSection.smartTools:
        return _buildSmartToolsContent(isDark: isDark);
      case _DesktopSettingsSection.security:
        return _buildSecurityContent(user: user, isDark: isDark);
    }
  }

  // 1. Profile Section Content
  Widget _buildProfileContent({required AppUser user, required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileHero(
          user: user,
          uploadingAvatar: _uploadingAvatar,
          onPickAvatar: _pickAvatar,
        ),
        const SizedBox(height: 24),

        _InsetGroup(
          title: 'المعلومات الأساسية والصلاحيات',
          children: [
            _InsetListTile(
              icon: Icons.work_rounded,
              iconColor: const Color(0xFF007AFF),
              title: 'المسمى الوظيفي والفرع',
              trailing: Text(
                user.jobTitle.isNotEmpty ? user.jobTitle : 'غير محدد (يمكنك إضافته بالأسفل)',
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
                user.can('canCreateUsers') ? 'صلاحيات إدارية متقدمة' : 'صلاحيات مستخدم قياسي',
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

        Form(
          key: _formKey,
          child: _InsetGroup(
            title: 'تحديث البيانات الشخصية والفرع',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'كلمة مرور جديدة',
                    hintText: 'اتركها فارغة إذا كنت لا تريد تغييرها',
                    prefixIcon: const Icon(Icons.key_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
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
      ],
    );
  }

  // 2. Appearance Section Content
  Widget _buildAppearanceContent({
    required UserPreferences preferences,
    required bool isDark,
  }) {
    final currentMode = ref.watch(themeModeControllerProvider).valueOrNull ?? ThemeMode.system;
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final chatPrefs = authUser?.chatPreferences ?? ChatPreferences.defaults;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mode Selector Cards
        _InsetGroup(
          title: 'نمط التطبيق العام (Theme Mode)',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _ThemeModeCard(
                      title: 'الوضع النهاري',
                      icon: Icons.light_mode_rounded,
                      iconColor: const Color(0xFFFF9500),
                      isSelected: currentMode == ThemeMode.light,
                      isDark: isDark,
                      onTap: () => ref.read(themeModeControllerProvider.notifier).setThemeMode(ThemeMode.light),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ThemeModeCard(
                      title: 'الوضع الليلي',
                      icon: Icons.dark_mode_rounded,
                      iconColor: const Color(0xFF5856D6),
                      isSelected: currentMode == ThemeMode.dark,
                      isDark: isDark,
                      onTap: () => ref.read(themeModeControllerProvider.notifier).setThemeMode(ThemeMode.dark),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ThemeModeCard(
                      title: 'تلقائي النظام',
                      icon: Icons.brightness_auto_rounded,
                      iconColor: const Color(0xFF007AFF),
                      isSelected: currentMode == ThemeMode.system,
                      isDark: isDark,
                      onTap: () => ref.read(themeModeControllerProvider.notifier).setThemeMode(ThemeMode.system),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Quick Chat Theme Selection (Apple / Modern Style)
        _InsetGroup(
          title: 'ثيمات الشات المميّزة (تطبيق فوري بضغطة واحدة)',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final activeThemeId = chatPrefs.themeId;
                  final quickThemes = [
                    (
                      id: 'festive_winter',
                      title: 'رأس السنة والجليد ❄️',
                      subtitle: 'تأثير الثلج على الحواف',
                      wpId: 'wp_winter_snow',
                      color: const Color(0xFF0284C7),
                      badge: 'احتفالي ❄️',
                    ),
                    (
                      id: 'festive_halloween',
                      title: 'هالوين الاحتفالي 🎃',
                      subtitle: 'أجواء اليقطين والظلال',
                      wpId: 'wp_halloween',
                      color: const Color(0xFFEA580C),
                      badge: 'احتفالي 🎃',
                    ),
                    (
                      id: 'telegram_night',
                      title: 'ليل تلجرام ✈️',
                      subtitle: 'كحلي ليلي راقي',
                      wpId: 'tg_night',
                      color: const Color(0xFF2AABEE),
                      badge: 'الأكثر شعبية',
                    ),
                    (
                      id: 'whatsapp',
                      title: 'واتساب الرسمي 💬',
                      subtitle: 'النمط الكلاسيكي الأصلي',
                      wpId: 'wa_classic',
                      color: const Color(0xFF00A884),
                      badge: 'كلاسيكي',
                    ),
                    (
                      id: 'sage_harmony',
                      title: 'راحة وحماية العين 👁️',
                      subtitle: 'Zero Blue دافئ ومريح',
                      wpId: 'grad_eye_comfort',
                      color: const Color(0xFF5F8D76),
                      badge: 'صحي للعين',
                    ),
                  ];

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: quickThemes.map((t) {
                      final isSelected = activeThemeId == t.id;
                      return SizedBox(
                        width: (constraints.maxWidth - 24) / 2 > 260
                            ? (constraints.maxWidth - 24) / 3
                            : (constraints.maxWidth - 12) / 2,
                        child: InkWell(
                          onTap: () async {
                            final next = chatPrefs.copyWith(
                              themeId: t.id,
                              wallpaperId: t.wpId,
                            );
                            await ref
                                .read(authControllerProvider.notifier)
                                .updateChatPreferences(next);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('تم تفعيل ${t.title} بنجاح!'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? (isSelected
                                      ? t.color.withValues(alpha: 0.16)
                                      : const Color(0xFF232326))
                                  : (isSelected
                                      ? t.color.withValues(alpha: 0.08)
                                      : const Color(0xFFF7F7FA)),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? t.color
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.06)),
                                width: isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: t.color.withValues(alpha: 0.20),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: isSelected
                                        ? Icon(Icons.check_circle_rounded, color: t.color, size: 22)
                                        : Container(
                                            width: 14,
                                            height: 14,
                                            decoration: BoxDecoration(
                                              color: t.color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        t.title,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          fontSize: 13,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        t.subtitle,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Appearance Studio Direct Banner
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                  : [const Color(0xFFE0F2FE), const Color(0xFFF0F9FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF0284C7).withValues(alpha: 0.25),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: Text('❄️', style: TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'استوديو مظهر وثيمات الشات المتكامل',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'استكشف ثيم رأس السنة والجليد ❄️ مع تأثير الثلج على حواف الرسائل، وأناقة تلجرام، وثيمات راحة العين Zero Blue Light.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatAppearanceScreen()),
                  );
                },
                icon: const Icon(Icons.palette_rounded, size: 18),
                label: const Text('فتح الاستوديو'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Chat Behavior Options
        _InsetGroup(
          title: 'سلوك صندوق المحادثة والإرسال',
          children: [
            SwitchListTile.adaptive(
              value: preferences.enterSendsMessage,
              onChanged: (value) => ref
                  .read(userPreferencesControllerProvider.notifier)
                  .setEnterSendsMessage(value),
              title: const Text(
                'زر Enter يرسل الرسالة فوراً',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'إذا تم التعطيل، زر Enter سينشئ سطرًا جديدًا والإرسال عبر زر السهم أو Ctrl+Enter.',
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
                'حفظ تلقائي باسم افتراضي بعد المسح الضوئي',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'إذا تم التعطيل، سيُطلب اسم الملف يدويًا قبل حفظ مستند الـ PDF.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 3. Notifications Section Content
  Widget _buildNotificationsContent({
    required UserPreferences preferences,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsetGroup(
          title: 'نغمة الإشعارات والتنبيه الصوتي',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: preferences.notificationToneId,
                      decoration: const InputDecoration(
                        labelText: 'اختر نغمة التنبيه',
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
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      ref
                          .read(localNotificationServiceProvider)
                          .previewNotificationTone(preferences.notificationToneId);
                    },
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: const Text('تجربة النغمة'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        _InsetGroup(
          title: 'أسلوب ظهور التنبيهات على الشاشة (Banner Style)',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: DropdownButtonFormField<String>(
                value: preferences.notificationDisplayModeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'طريقة عرض الإشعار',
                  prefixIcon: Icon(Icons.visibility_outlined, size: 20),
                  border: InputBorder.none,
                ),
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
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
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
      ],
    );
  }

  // 4. Storage Section Content
  Widget _buildStorageContent({
    required UserPreferences preferences,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cache Cleaner Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF5856D6).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.cleaning_services_rounded,
                  color: Color(0xFF5856D6),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إدارة مساحة التخزين والذاكرة المؤقتة (Cache Cleaner)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'تفريغ كاش التطبيق، ومصغرات الصور، والملفات المؤقتة لتسريع الأداء وتوفير المساحة.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DesktopStorageManagementScreen(),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5856D6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('إدارة الكاش والذاكرة'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        _InsetGroup(
          title: 'مسارات الحفظ والتخزين على القرص الصلب',
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
                'مجلد ملفات المسح الضوئي (PDF)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                preferences.scanSaveDirectoryPath ?? 'المسار الافتراضي للمنظومة',
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: _pickScanSaveDirectory,
                child: const Text('تغيير المجلد'),
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
                'مجلد تخزين الصور ومرفقات الشات',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                preferences.localStorageDirectoryPath ?? 'المسار الافتراضي للمنظومة',
                style: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: _pickLocalStorageDirectory,
                child: const Text('تغيير المجلد'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 5. Smart Tools Section Content
  Widget _buildSmartToolsContent({required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsetGroup(
          title: 'أدوات الإنتاجية والشات المتقدمة',
          children: [
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.content_paste_go_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              title: const Text(
                'الحافظة المشتركة الفورية (الكمبيوتر ⇄ الموبايل)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'مزامنة النصوص والأكواد والروابط المنسوخة لحظياً بين جميع أجهزتك',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: () => showDesktopInstantClipboardSyncDialog(context, ref),
                child: const Text('فتح الحافظة'),
              ),
            ),
            const Divider(height: 0.5, indent: 52),
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              title: const Text(
                'الردود السريعة والقوالب الجاهزة (/)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'قوالب رسائل جاهزة تظهر تلقائياً بمجرد كتابة / في صندوق الرسائل',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: () => showDesktopQuickRepliesDialog(context),
                child: const Text('تخصيص الردود'),
              ),
            ),
            const Divider(height: 0.5, indent: 52),
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFFF59E0B),
                  size: 20,
                ),
              ),
              title: const Text(
                'تذكيرات الرسائل المجدولة',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'استعراض وإدارة التنبيهات المجدولة للرسائل والمهام الهامة',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: () => showDesktopRemindersListDialog(context),
                child: const Text('عرض التذكيرات'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 6. Security Section Content
  Widget _buildSecurityContent({required AppUser user, required bool isDark}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsetGroup(
          title: 'إدارة الجلسات والأجهزة النشطة',
          children: [
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.devices_rounded,
                  color: Color(0xFF0EA5E9),
                  size: 20,
                ),
              ),
              title: const Text(
                'الأجهزة المتصلة والجلسات المفتوحة',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'عرض كافة الهواتف وأجهزة الكمبيوتر المسجلة حالياً وتسجيل الخروج منها عن بُعد',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: () => showDesktopActiveSessionsDialog(context),
                child: const Text('إدارة الأجهزة'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Danger Zone
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withValues(alpha: isDark ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFDC2626).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFDC2626),
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تسجيل الخروج من الحساب',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'سيتم إنهاء جلستك الحالية والعودة إلى شاشة تسجيل الدخول.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => _confirmLogout(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar Components
// ─────────────────────────────────────────────────────────────────────────────
class _SidebarUserHeader extends StatelessWidget {
  const _SidebarUserHeader({
    required this.user,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
  });

  final AppUser user;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        color: isSelected
            ? cs.primary.withValues(alpha: isDark ? 0.12 : 0.08)
            : Colors.transparent,
        child: Row(
          children: [
            SafeNetworkAvatar(
              radius: 24,
              backgroundColor: cs.primary.withValues(alpha: 0.12),
              imageUrl: user.avatarUrl,
              fallbackText: user.fullName.isNotEmpty
                  ? user.fullName.trim().characters.first
                  : user.username.characters.first,
              fallbackTextStyle: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.fullName.isNotEmpty ? user.fullName : user.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.jobTitle.isNotEmpty ? user.jobTitle : '@${user.username}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  const _SidebarNavTile({
    required this.section,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final _DesktopSettingsSection section;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Material(
        color: isSelected
            ? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: section.accentColor.withValues(alpha: isSelected ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    section.icon,
                    color: section.accentColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                          : cs.onSurface,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: section.accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.isDark,
    required this.onLogout,
  });

  final bool isDark;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'iSmart Messenger v1.0',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
              fontWeight: FontWeight.w500,
            ),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(
              Icons.logout_rounded,
              size: 18,
              color: Color(0xFFDC2626),
            ),
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

class _SectionTopHeader extends StatelessWidget {
  const _SectionTopHeader({
    required this.section,
    required this.isDark,
  });

  final _DesktopSettingsSection section;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141416) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF262628) : const Color(0xFFEDEDF2),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: section.accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              section.icon,
              color: section.accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  section.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
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

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? iconColor.withValues(alpha: isDark ? 0.18 : 0.10)
              : (isDark ? const Color(0xFF252528) : const Color(0xFFF7F7FA)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
                color: isSelected ? iconColor : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Inset Group & Hero Widgets
// ─────────────────────────────────────────────────────────────────────────────
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

          Text(
            user.fullName.isNotEmpty ? user.fullName : user.username,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),

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

// ─────────────────────────────────────────────────────────────────────────────
// Interactive Image Cropper Dialog
// ─────────────────────────────────────────────────────────────────────────────
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
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E242B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'تعديل وتحديد الصورة الشخصية',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                height: 260,
                child: ClipOval(
                  child: RepaintBoundary(
                    key: _boundaryKey,
                    child: Container(
                      color: Colors.black,
                      child: InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 0.5,
                        maxScale: 3.5,
                        onInteractionUpdate: (details) {
                          final currentScale =
                              _transformController.value.getMaxScaleOnAxis();
                          if ((_zoomLevel - currentScale).abs() > 0.05) {
                            setState(() {
                              _zoomLevel = currentScale.clamp(1.0, 3.0);
                            });
                          }
                        },
                        child: RotatedBox(
                          quarterTurns: _rotationQuarterTurns,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.cover,
                            width: 260,
                            height: 260,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.zoom_out_rounded, size: 18),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _zoomLevel.clamp(1.0, 3.0),
                        min: 1.0,
                        max: 3.0,
                        onChanged: _onSliderZoomChanged,
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in_rounded, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _rotate,
                    icon: const Icon(Icons.rotate_right_rounded, size: 18),
                    label: const Text('تدوير 90°'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _reset,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('إعادة ضبط'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
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
                      label: Text(_isProcessing ? 'معالجة...' : 'اعتماد وحفظ'),
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
