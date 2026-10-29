import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/settings/user_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/button_loading_indicator.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import 'storage_management_screen.dart';
import 'notification_settings_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

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
  bool _obscurePassword = true;

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
      await ref
          .read(authControllerProvider.notifier)
          .updateProfile(
            fullName: _fullNameController.text.trim(),
            jobTitle: _jobTitleController.text.trim(),
            password: _passwordController.text.trim(),
          );
      if (!mounted) return;
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ التعديلات بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
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
      if (filePath == null || filePath.isEmpty) return;

      await ref.read(authControllerProvider.notifier).uploadAvatar(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث الصورة الشخصية')));
    } catch (error) {
      if (!mounted) return;
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث مسار حفظ ملفات المسح')),
      );
    } catch (error) {
      if (!mounted) return;
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
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('إعادة تشغيل التطبيق'),
          content: const Text(
            'تم تحديث مجلد التخزين. يرجى إعادة تشغيل التطبيق لقراءة الملفات من المسار الجديد.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث مسار تخزين الملفات')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 26),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'تسجيل الخروج',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'هل أنت متأكد من رغبتك في تسجيل الخروج من هذا الحساب؟',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('خروج'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final userPreferencesState = ref.watch(userPreferencesControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text(
          'الملف الشخصي والإعدادات',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17.5),
        ),
        backgroundColor: scaffoldBg,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: authState.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ShimmerSkeleton(height: 140, borderRadius: 24),
            SizedBox(height: 16),
            ShimmerSkeleton(height: 260, borderRadius: 20),
            SizedBox(height: 16),
            ShimmerSkeleton(height: 180, borderRadius: 20),
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
          if (_jobTitleController.text.isEmpty && user.jobTitle.isNotEmpty) {
            _jobTitleController.text = user.jobTitle;
          }

          final preferences =
              userPreferencesState.valueOrNull ?? UserPreferences.defaults();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              // ── Apple Hero Avatar & Info Card ──
              _AppleProfileHero(
                user: user,
                uploadingAvatar: _uploadingAvatar,
                onPickAvatar: _pickAvatar,
              ),
              const SizedBox(height: 20),

              // ── Section 1: Account Information (Inset Grouped) ──
              _AppleSectionHeader(title: 'البيانات الشخصية والوظيفة', icon: Icons.badge_outlined),
              _AppleInsetGroup(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _AppleSettingsInputField(
                          controller: _fullNameController,
                          label: 'الاسم الكامل',
                          hint: 'اسمك المعروض للموظفين',
                          icon: Icons.person_rounded,
                          validator: (value) {
                            if (value == null || value.trim().length < 2) {
                              return 'الاسم الكامل مطلوب';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _AppleSettingsInputField(
                          controller: _jobTitleController,
                          label: 'المسمى الوظيفي',
                          hint: 'مثال: محاسب، مدير فرع، مهندس IT...',
                          icon: Icons.work_outline_rounded,
                        ),
                        const SizedBox(height: 12),
                        _AppleSettingsInputField(
                          controller: TextEditingController(
                            text: user.branchCode.isNotEmpty ? user.branchCode : 'الفرع الرئيسي',
                          ),
                          enabled: false,
                          label: 'الفرع التابع له',
                          icon: Icons.storefront_rounded,
                        ),
                        const SizedBox(height: 12),
                        _AppleSettingsInputField(
                          controller: TextEditingController(text: user.username),
                          enabled: false,
                          label: 'اسم المستخدم (Username)',
                          icon: Icons.alternate_email_rounded,
                        ),
                        const SizedBox(height: 12),
                        _AppleSettingsInputField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          label: 'تغيير كلمة المرور',
                          hint: 'اتركها فارغة للإبقاء على الحالية',
                          icon: Icons.lock_outline_rounded,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 19,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _saveProfile,
                            icon: _saving ? null : const Icon(Icons.check_rounded, size: 18),
                            label: _saving
                                ? const SizedBox(width: 18, height: 18, child: ButtonLoadingIndicator())
                                : const Text('حفظ التغييرات', style: TextStyle(fontWeight: FontWeight.w700)),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF007AFF),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Section 2: Chat & Messaging Preferences ──
              _AppleSectionHeader(title: 'تفضيلات المحادثات والدردشة', icon: Icons.chat_bubble_outline_rounded),
              _AppleInsetGroup(
                child: Column(
                  children: [
                    _AppleSettingsSwitchTile(
                      icon: Icons.keyboard_return_rounded,
                      iconColor: const Color(0xFF34C759),
                      title: 'زر Enter يرسل الرسالة',
                      subtitle: 'عند التعطيل، يفتح Enter سطراً جديداً والإرسال عبر زر السهم',
                      value: preferences.enterSendsMessage,
                      onChanged: (val) => ref
                          .read(userPreferencesControllerProvider.notifier)
                          .setEnterSendsMessage(val),
                    ),
                    const _AppleDivider(),
                    _AppleSettingsSwitchTile(
                      icon: Icons.document_scanner_rounded,
                      iconColor: const Color(0xFF007AFF),
                      title: 'حفظ تلقائي للمستندات بعد المسح',
                      subtitle: 'تسمية وحفظ ملفات الـ PDF تلقائياً دون طلب الاسم',
                      value: preferences.autoSaveAfterScan,
                      onChanged: (val) => ref
                          .read(userPreferencesControllerProvider.notifier)
                          .setAutoSaveAfterScan(val),
                    ),
                    const _AppleDivider(),
                    _AppleSettingsNavTile(
                      icon: Icons.notifications_active_rounded,
                      iconColor: const Color(0xFFFF9500),
                      title: 'إعدادات الإشعارات والتنبيهات',
                      subtitle: 'تخصيص النغمات، تجميع المحادثات كواتساب، والاهتزاز',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Section 3: Storage & Cache Management ──
              _AppleSectionHeader(title: 'التخزين والملفات والذاكرة', icon: Icons.folder_outlined),
              _AppleInsetGroup(
                child: Column(
                  children: [
                    _AppleSettingsNavTile(
                      icon: Icons.cleaning_services_rounded,
                      iconColor: const Color(0xFF5856D6),
                      title: 'إدارة مساحة التخزين والكاش',
                      subtitle: 'تفريغ الذاكرة المؤقتة وتسريع الهاتف دون حذف الرسائل',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StorageManagementScreen(),
                          ),
                        );
                      },
                    ),
                    const _AppleDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.folder_open_rounded, color: Color(0xFF007AFF), size: 18),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'مجلد حفظ ملفات المسح (PDF)',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(right: 44),
                            child: Text(
                              preferences.scanSaveDirectoryPath ?? 'المسار الافتراضي داخل التطبيق',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(right: 44),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonal(
                                  onPressed: _pickScanSaveDirectory,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    textStyle: const TextStyle(fontSize: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('اختيار مجلد'),
                                ),
                                if (preferences.scanSaveDirectoryPath != null)
                                  TextButton(
                                    onPressed: () => ref
                                        .read(userPreferencesControllerProvider.notifier)
                                        .setScanSaveDirectoryPath(null),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                    child: const Text('إعادة الافتراضي'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const _AppleDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34C759).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.folder_copy_rounded, color: Color(0xFF34C759), size: 18),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'مجلد تخزين الصور والمرفقات',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(right: 44),
                            child: Text(
                              preferences.localStorageDirectoryPath ?? 'iSmart Messenger / Storage داخل مساحة التطبيق',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white54 : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(right: 44),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonal(
                                  onPressed: _pickLocalStorageDirectory,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    textStyle: const TextStyle(fontSize: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('اختيار مجلد'),
                                ),
                                if (preferences.localStorageDirectoryPath != null)
                                  TextButton(
                                    onPressed: () => ref
                                        .read(userPreferencesControllerProvider.notifier)
                                        .setLocalStorageDirectoryPath(null),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                    child: const Text('إعادة الافتراضي'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Section 4: About & System ──
              _AppleSectionHeader(title: 'عن التطبيق والأمان', icon: Icons.shield_outlined),
              _AppleInsetGroup(
                child: Column(
                  children: [
                    _AppleSettingsNavTile(
                      icon: Icons.privacy_tip_outlined,
                      iconColor: const Color(0xFF007AFF),
                      title: 'سياسة الخصوصية وأمان البيانات',
                      subtitle: 'Privacy Policy & Data Security',
                      onTap: () async {
                        final baseUrl = ref.read(apiBaseUrlControllerProvider).valueOrNull ?? AppConfig.defaultApiBaseUrl;
                        final uri = Uri.parse(baseUrl.endsWith('/') ? '${baseUrl}privacy-policy' : '$baseUrl/privacy-policy');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const _AppleDivider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8E8E93).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.info_outline_rounded, color: Color(0xFF8E8E93), size: 18),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'إصدار المنظومة',
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'v1.1.3',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Logout Destructive Button ──
              _AppleInsetGroup(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _confirmLogout,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'تسجيل الخروج من الحساب',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ─── Apple Settings Widgets ───────────────────────────────────────────────────

class _AppleSectionHeader extends StatelessWidget {
  const _AppleSectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppleInsetGroup extends StatelessWidget {
  const _AppleInsetGroup({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _AppleDivider extends StatelessWidget {
  const _AppleDivider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 0.8,
      thickness: 0.8,
      indent: 52,
      color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
    );
  }
}

class _AppleSettingsInputField extends StatelessWidget {
  const _AppleSettingsInputField({
    required this.controller,
    required this.label,
    this.hint,
    required this.icon,
    this.enabled = true,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool enabled;
  final bool obscureText;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          validator: validator,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
            ),
            filled: true,
            fillColor: enabled
                ? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF8FAFC))
                : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
            prefixIcon: Icon(icon, size: 18, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                width: 0.8,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                width: 0.8,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0),
                width: 0.8,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppleSettingsSwitchTile extends StatelessWidget {
  const _AppleSettingsSwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: const Color(0xFF34C759),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _AppleSettingsNavTile extends StatelessWidget {
  const _AppleSettingsNavTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white54 : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleProfileHero extends StatelessWidget {
  const _AppleProfileHero({
    required this.user,
    required this.uploadingAvatar,
    required this.onPickAvatar,
  });

  final AppUser user;
  final bool uploadingAvatar;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOnline = user.presenceStatus == 'online';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          // Avatar with Camera Badge
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE2E8F0),
                    border: Border.all(
                      color: isDark ? Colors.white10 : const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                  ),
                  child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: user.avatarUrl!,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: AppLoadingIndicator(size: 22),
                            ),
                            errorWidget: (_, __, ___) => _InitialLetter(name: user.fullName.isNotEmpty ? user.fullName : user.username),
                          ),
                        )
                      : _InitialLetter(name: user.fullName.isNotEmpty ? user.fullName : user.username),
                ),
                // Camera Button Badge
                PositionedDirectional(
                  bottom: -2,
                  end: -2,
                  child: GestureDetector(
                    onTap: uploadingAvatar ? null : onPickAvatar,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: uploadingAvatar
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Name
          Text(
            user.fullName.isNotEmpty ? user.fullName : user.username,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          // Badges Wrap (Username, Role, Branch)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              _HeroPill(
                icon: Icons.alternate_email_rounded,
                label: user.username,
                color: const Color(0xFF007AFF),
              ),
              _HeroPill(
                icon: user.role == 'admin' ? Icons.shield_rounded : Icons.person_rounded,
                label: user.role == 'admin' ? 'مسؤول نظام' : 'موظف',
                color: user.role == 'admin' ? const Color(0xFFEA580C) : const Color(0xFF64748B),
              ),
              if (user.branchCode.isNotEmpty)
                _HeroPill(
                  icon: Icons.storefront_rounded,
                  label: 'فرع ${user.branchCode}',
                  color: const Color(0xFF9333EA),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Status indicator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? const Color(0xFF34C759) : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isOnline ? 'متصل الآن' : (user.lastSeen != null ? 'آخر ظهور ${formatEgyptDateTime(user.lastSeen!)}' : 'غير متصل'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InitialLetter extends StatelessWidget {
  const _InitialLetter({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isNotEmpty ? name.trim().characters.first.toUpperCase() : 'U';
    return Center(
      child: Text(
        letter,
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF007AFF)),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
