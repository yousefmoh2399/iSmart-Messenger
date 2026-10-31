import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/settings/user_preferences.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../chat/presentation/chat_admin_management_screen.dart';
import '../../chat/presentation/chat_appearance_screen.dart';
import '../../chat/presentation/conversation_screen.dart';
import '../../chat/presentation/favorite_messages_screen.dart';
import '../../chat/presentation/widgets/create_chat_folder_dialog.dart';
import '../../chat/presentation/widgets/instant_clipboard_sync_sheet.dart';
import '../../chat/presentation/widgets/message_reminder_sheet.dart';
import '../../chat/presentation/widgets/quick_replies_sheet.dart';
import '../../files/presentation/my_files_screen.dart';
import '../../it_assets/presentation/mobile_it_asset_scanner_screen.dart';
import '../../printers/presentation/printer_monitoring_screen.dart';
import '../../tickets/presentation/tickets_screen.dart';
import 'active_sessions_screen.dart';
import 'notification_settings_screen.dart';
import 'storage_management_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    this.isEmbeddedInTab = false,
  });

  final bool isEmbeddedInTab;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الصورة الشخصية بنجاح')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _showEditProfileModal(BuildContext context, AppUser user) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(user: user),
    );
  }

  Future<void> _showChangePasswordModal(BuildContext context, AppUser user) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangePasswordSheet(user: user),
    );
  }

  Future<void> _showStorageDirectoriesSheet(
    BuildContext context,
    UserPreferences preferences,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final sheetBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

        return Consumer(
          builder: (context, ref, _) {
            final prefs = ref.watch(userPreferencesControllerProvider).valueOrNull ??
                preferences;

            return Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'مجلدات الحفظ والتخزين',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'تخصيص أماكن حفظ المستندات والملفات على جهازك',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 1. Scan PDF Folder
                  _buildFolderConfigCard(
                    title: 'مجلد حفظ ملفات المسح (PDF)',
                    path: prefs.scanSaveDirectoryPath ??
                        'المسار الافتراضي داخل التطبيق',
                    isCustom: prefs.scanSaveDirectoryPath != null,
                    isDark: isDark,
                    onPick: () async {
                      final selected =
                          await FilePicker.platform.getDirectoryPath(
                        dialogTitle: 'اختر مجلد حفظ ملفات المسح',
                      );
                      if (selected != null && selected.trim().isNotEmpty) {
                        await ref
                            .read(userPreferencesControllerProvider.notifier)
                            .setScanSaveDirectoryPath(selected.trim());
                      }
                    },
                    onReset: () => ref
                        .read(userPreferencesControllerProvider.notifier)
                        .setScanSaveDirectoryPath(null),
                  ),
                  const SizedBox(height: 14),

                  // 2. Storage Attachments Folder
                  _buildFolderConfigCard(
                    title: 'مجلد تخزين المرفقات والصور',
                    path: prefs.localStorageDirectoryPath ??
                        'iSmart Messenger Storage (داخل مساحة التطبيق)',
                    isCustom: prefs.localStorageDirectoryPath != null,
                    isDark: isDark,
                    onPick: () async {
                      final current = prefs.localStorageDirectoryPath;
                      final selected =
                          await FilePicker.platform.getDirectoryPath(
                        dialogTitle: 'اختر مجلد تخزين الصور والمستندات',
                        initialDirectory: current,
                      );
                      if (selected != null && selected.trim().isNotEmpty) {
                        await ref
                            .read(userPreferencesControllerProvider.notifier)
                            .setLocalStorageDirectoryPath(selected.trim());
                      }
                    },
                    onReset: () => ref
                        .read(userPreferencesControllerProvider.notifier)
                        .setLocalStorageDirectoryPath(null),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFolderConfigCard({
    required String title,
    required String path,
    required bool isCustom,
    required bool isDark,
    required VoidCallback onPick,
    required VoidCallback onReset,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            path,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: onPick,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('اختيار مجلد'),
              ),
              if (isCustom) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onReset,
                  style: TextButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('استعادة الافتراضي'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showChangeServerUrlDialog(BuildContext context) async {
    final currentUrl = ref.read(apiBaseUrlControllerProvider).valueOrNull ??
        AppConfig.defaultApiBaseUrl;

    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => _ChangeServerUrlDialog(initialUrl: currentUrl),
    );

    if (newUrl == '__reset__') {
      await ref.read(apiBaseUrlControllerProvider.notifier).reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت استعادة الرابط الافتراضي للخادم')),
        );
      }
    } else if (newUrl != null && newUrl.isNotEmpty) {
      await ref.read(apiBaseUrlControllerProvider.notifier).save(newUrl);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديث رابط الخادم إلى: $newUrl')),
        );
      }
    }
  }

  Future<void> _openSavedMessagesDirect(String currentUserId) async {
    try {
      final conv = await ref
          .read(chatOverviewControllerProvider.notifier)
          .openOrCreateSavedMessages(currentUserId);
      if (mounted) {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => ConversationScreen(conversation: conv),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الرسائل المحفوظة: $e')),
        );
      }
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
                      child: Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFEF4444),
                        size: 26,
                      ),
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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
    final scaffoldBg =
        isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);

    final content = authState.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ShimmerSkeleton(height: 160, borderRadius: 24),
          SizedBox(height: 16),
          ShimmerSkeleton(height: 180, borderRadius: 20),
          SizedBox(height: 16),
          ShimmerSkeleton(height: 200, borderRadius: 20),
        ],
      ),
      error: (error, _) => Center(child: Text(error.toString())),
      data: (user) {
        if (user == null) {
          return const Center(child: Text('لا توجد بيانات للمستخدم'));
        }

        final preferences =
            userPreferencesState.valueOrNull ?? UserPreferences.defaults();

        final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
        final dividerColor =
            isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

        final canAdmin = user.can('canCreateUsers') == true ||
            user.can('canCreateDepartments') == true ||
            user.role == 'admin';
        final canPrinters =
            user.canViewPrinterModule == true || user.role == 'admin';
        final canItAssets = user.canScanItAssets == true ||
            user.canScanItSpareParts == true ||
            user.canScanItInventory == true ||
            user.role == 'admin';

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.isEmbeddedInTab ? 10 : 16,
            16,
            widget.isEmbeddedInTab ? 100 : 40,
          ),
          children: [
            // ── Top Apple Hero Card ──────────────────────────────────────────
            _buildProfileHeroCard(user, isDark),
            const SizedBox(height: 18),

            // ── Group 1: Appearance & Display ────────────────────────────────
            _buildSectionTitle('المظهر والعرض', isDark),
            _buildAppleGroup(
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _AppleTile(
                  icon: isDark
                      ? CupertinoIcons.moon_fill
                      : CupertinoIcons.sun_max_fill,
                  iconColor: const Color(0xFFFF9500),
                  label: 'الوضع الداكن (Dark Mode)',
                  subtitle: isDark
                      ? 'الوضع الليلي مفعّل حالياً'
                      : 'الوضع النهاري مفعّل حالياً',
                  trailing: CupertinoSwitch(
                    value: isDark,
                    activeTrackColor: const Color(0xFF007AFF),
                    onChanged: (val) {
                      ref
                          .read(themeModeControllerProvider.notifier)
                          .setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
                    },
                  ),
                  onTap: () {
                    ref.read(themeModeControllerProvider.notifier).setThemeMode(
                          isDark ? ThemeMode.light : ThemeMode.dark,
                        );
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.paintbrush_fill,
                  iconColor: const Color(0xFFAF52DE),
                  label: 'مظهر وألوان المحادثات',
                  subtitle: 'تخصيص ثيمات الشات وفقاعات الرسائل',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChatAppearanceScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Group 2: Chat & Messaging ────────────────────────────────────
            _buildSectionTitle('المحادثات والتواصل', isDark),
            _buildAppleGroup(
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _AppleTile(
                  icon: CupertinoIcons.return_icon,
                  iconColor: const Color(0xFF34C759),
                  label: 'زر Enter يرسل الرسالة',
                  subtitle:
                      'عند التعطيل، يفتح Enter سطراً جديداً والإرسال عبر زر السهم',
                  trailing: CupertinoSwitch(
                    value: preferences.enterSendsMessage,
                    activeTrackColor: const Color(0xFF34C759),
                    onChanged: (val) {
                      ref
                          .read(userPreferencesControllerProvider.notifier)
                          .setEnterSendsMessage(val);
                    },
                  ),
                  onTap: () {
                    ref
                        .read(userPreferencesControllerProvider.notifier)
                        .setEnterSendsMessage(!preferences.enterSendsMessage);
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.bookmark_fill,
                  iconColor: const Color(0xFF5856D6),
                  label: 'الرسائل المحفوظة (الملاحظات الذاتية)',
                  subtitle: 'مساحتك السحابية لحفظ الملاحظات، الروابط، والمستندات',
                  onTap: () => _openSavedMessagesDirect(user.id),
                ),
                _AppleTile(
                  icon: CupertinoIcons.star_fill,
                  iconColor: const Color(0xFFFFCC00),
                  label: 'الرسائل المفضلة',
                  subtitle: 'الرسائل المحفوظة للرجوع السريع إليها',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FavoriteMessagesScreen(),
                      ),
                    );
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.bolt_horizontal_circle_fill,
                  iconColor: const Color(0xFF007AFF),
                  label: 'الردود السريعة والقوالب الجاهزة (/)',
                  subtitle: 'إضافة وتخصيص ردودك الجاهزة التي تظهر عند كتابة / في الشات',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QuickRepliesManagementScreen(),
                      ),
                    );
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.alarm_fill,
                  iconColor: const Color(0xFFFF9500),
                  label: 'تذكيرات الرسائل',
                  subtitle: 'استعراض وإدارة تذكيرات المهام والرسائل المجدولة للتنبيه',
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => MessageRemindersSheet(
                        onJumpToMessage: (reminder) {
                          final overview =
                              ref.read(chatOverviewControllerProvider).valueOrNull;
                          final conv = overview?.conversations
                              .where((c) => c.id == reminder.conversationId)
                              .firstOrNull;
                          if (conv != null && mounted) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ConversationScreen(
                                  conversation: conv,
                                  initialMessageId: reminder.messageId,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.folder_badge_plus,
                  iconColor: const Color(0xFF007AFF),
                  label: 'مجلدات وتصنيفات الشات',
                  subtitle: 'إنشاء مجلدات مخصصة لفرز محادثاتك',
                  onTap: () async {
                    final overview = ref
                        .read(chatOverviewControllerProvider)
                        .valueOrNull;
                    await showCreateOrEditChatFolderDialog(
                      context,
                      availableConversations:
                          overview?.conversations ?? const [],
                      currentUserId: user.id,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Group 3: Notifications ───────────────────────────────────────
            _buildSectionTitle('الإشعارات والتنبيهات', isDark),
            _buildAppleGroup(
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _AppleTile(
                  icon: CupertinoIcons.bell_fill,
                  iconColor: const Color(0xFFFF3B30),
                  label: 'إعدادات الإشعارات والتنبيهات',
                  subtitle:
                      'نغمات الرسائل، الاهتزاز، وتجميع المحادثات كواتساب',
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
            const SizedBox(height: 18),

            // ── Group 4: Storage & Files ─────────────────────────────────────
            _buildSectionTitle('التخزين والملفات والذاكرة', isDark),
            _buildAppleGroup(
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _AppleTile(
                  icon: CupertinoIcons.circle_grid_hex_fill,
                  iconColor: const Color(0xFF34C759),
                  label: 'إدارة مساحة التخزين والكاش',
                  subtitle:
                      'تفريغ الذاكرة المؤقتة وتسريع الهاتف دون حذف المحادثات',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StorageManagementScreen(),
                      ),
                    );
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.doc_checkmark_fill,
                  iconColor: const Color(0xFF007AFF),
                  label: 'حفظ تلقائي للمستندات بعد المسح',
                  subtitle: 'تسمية وحفظ ملفات الـ PDF تلقائياً بعد المسح',
                  trailing: CupertinoSwitch(
                    value: preferences.autoSaveAfterScan,
                    activeTrackColor: const Color(0xFF007AFF),
                    onChanged: (val) {
                      ref
                          .read(userPreferencesControllerProvider.notifier)
                          .setAutoSaveAfterScan(val);
                    },
                  ),
                  onTap: () {
                    ref
                        .read(userPreferencesControllerProvider.notifier)
                        .setAutoSaveAfterScan(!preferences.autoSaveAfterScan);
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.folder_fill,
                  iconColor: const Color(0xFFFF9500),
                  label: 'مجلدات الحفظ والتخزين',
                  subtitle: 'تخصيص مسار حفظ مستندات PDF والمرفقات',
                  onTap: () =>
                      _showStorageDirectoriesSheet(context, preferences),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Group 5: Productivity & Cloud ────────────────────────────────
            _buildSectionTitle('الملفات والإنتاجية', isDark),
            _buildAppleGroup(
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _AppleTile(
                  icon: CupertinoIcons.cloud_fill,
                  iconColor: const Color(0xFF007AFF),
                  label: 'ملفاتي ومستنداتي السحابية',
                  subtitle: 'استعراض وإدارة كافة الملفات والمستندات المرفوعة',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyFilesScreen(),
                      ),
                    );
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.doc_on_clipboard_fill,
                  iconColor: const Color(0xFF00C7BE),
                  label: 'الحافظة المشتركة الفورية (Clipboard Sync)',
                  subtitle:
                      'نسخ النصوص والروابط والأكواد فوراً بين الموبايل والكمبيوتر',
                  onTap: () => showInstantClipboardSyncSheet(context, ref),
                ),
                _AppleTile(
                  icon: CupertinoIcons.device_laptop,
                  iconColor: const Color(0xFF5856D6),
                  label: 'إرسال ملف إلى الكمبيوتر',
                  subtitle: 'نقل سريع ومباشر للكمبيوتر عبر الشبكة',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyFilesScreen(
                          launchDesktopSendPickerOnOpen: true,
                        ),
                      ),
                    );
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.headphones,
                  iconColor: const Color(0xFFFF2D55),
                  label: 'تذاكر الدعم والشكاوى',
                  subtitle: 'إرسال ومتابعة بلاغات IT والمقترحات',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const TicketsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Group 6: Admin & System Tools (if permitted) ─────────────────
            if (canAdmin || canPrinters || canItAssets) ...[
              _buildSectionTitle('الأدوات الإدارية والشبكة', isDark),
              _buildAppleGroup(
                cardColor: cardColor,
                dividerColor: dividerColor,
                children: [
                  if (canAdmin)
                    _AppleTile(
                      icon: CupertinoIcons.shield_fill,
                      iconColor: const Color(0xFF34C759),
                      label: 'لوحة إدارة الشات والمستخدمين',
                      subtitle: 'إدارة المستخدمين والأقسام وسجلات النظام',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ChatAdminManagementScreen(),
                          ),
                        );
                      },
                    ),
                  if (canPrinters)
                    _AppleTile(
                      icon: CupertinoIcons.printer_fill,
                      iconColor: const Color(0xFF007AFF),
                      label: 'مراقبة أسطول الطابعات',
                      subtitle: 'فحص الطابعات والعدادات ومستويات الأحبار',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MobilePrinterMonitoringScreen(),
                          ),
                        );
                      },
                    ),
                  if (canItAssets)
                    _AppleTile(
                      icon: CupertinoIcons.barcode_viewfinder,
                      iconColor: const Color(0xFF00C7BE),
                      label: 'ماسح أصول IT والمخزون',
                      subtitle: 'جرد العتاد وقطع الغيار بالكاميرا والباركود',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MobileItAssetScannerScreen(),
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
            ],

            // ── Group 7: About & Legal ───────────────────────────────────────
            _buildSectionTitle('عن المنظومة والأمان', isDark),
            _buildAppleGroup(
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _AppleTile(
                  icon: CupertinoIcons.device_laptop,
                  iconColor: const Color(0xFF34C759),
                  label: 'الأجهزة المتصلة والجلسات النشطة',
                  subtitle:
                      'عرض الأجهزة المسجل الدخول منها وإنهاء الجلسات الأخرى',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ActiveSessionsScreen(),
                      ),
                    );
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.link,
                  iconColor: const Color(0xFF5856D6),
                  label: 'إعدادات الاتصال بالخادم',
                  subtitle: 'تعديل عنوان ورابط API الرئيسي',
                  onTap: () => _showChangeServerUrlDialog(context),
                ),
                _AppleTile(
                  icon: CupertinoIcons.lock_shield_fill,
                  iconColor: const Color(0xFF007AFF),
                  label: 'سياسة الخصوصية وأمان البيانات',
                  subtitle: 'Privacy Policy & Data Protection',
                  onTap: () async {
                    final baseUrl = ref
                            .read(apiBaseUrlControllerProvider)
                            .valueOrNull ??
                        AppConfig.defaultApiBaseUrl;
                    final uri = Uri.parse(
                      baseUrl.endsWith('/')
                          ? '${baseUrl}privacy-policy'
                          : '$baseUrl/privacy-policy',
                    );
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
                _AppleTile(
                  icon: CupertinoIcons.info_circle_fill,
                  iconColor: const Color(0xFF8E8E93),
                  label: 'إصدار التطبيق',
                  subtitle: 'iSmart Workplace Messenger',
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'v1.2.4',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // ── Group 8: Logout Action ───────────────────────────────────────
            _buildAppleGroup(
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _AppleTile(
                  icon: CupertinoIcons.square_arrow_right,
                  iconColor: const Color(0xFFFF3B30),
                  label: 'تسجيل الخروج',
                  subtitle: 'إنهاء الجلسة والخروج من الحساب الحالي',
                  isDestructive: true,
                  onTap: _confirmLogout,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );

    if (widget.isEmbeddedInTab) {
      return content;
    }

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
      body: content,
    );
  }

  // ── Profile Hero Card ──────────────────────────────────────────────────────

  Widget _buildProfileHeroCard(AppUser user, bool isDark) {
    final isOnline = user.presenceStatus == 'online';
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          // Avatar + Camera Badge
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE2E8F0),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                  ),
                  child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: user.avatarUrl!,
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: AppLoadingIndicator(size: 20),
                            ),
                            errorWidget: (_, __, ___) => _buildInitialLetter(
                              user.fullName.isNotEmpty
                                  ? user.fullName
                                  : user.username,
                            ),
                          ),
                        )
                      : _buildInitialLetter(
                          user.fullName.isNotEmpty
                              ? user.fullName
                              : user.username,
                        ),
                ),
                PositionedDirectional(
                  bottom: -1,
                  end: -1,
                  child: GestureDetector(
                    onTap: _uploadingAvatar ? null : _pickAvatar,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1C1C1E)
                              : Colors.white,
                          width: 2.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _uploadingAvatar
                            ? const SizedBox(
                                width: 14,
                                height: 14,
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
          ),
          const SizedBox(height: 12),

          // Name
          Text(
            user.fullName.isNotEmpty ? user.fullName : user.username,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),

          // Job Title (if present)
          if (user.jobTitle.isNotEmpty) ...[
            Text(
              user.jobTitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
          ],

          // Badges Wrap (Username, Role, Branch)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: user.username));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم نسخ اسم المستخدم: @${user.username}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: _buildPill(
                  icon: Icons.alternate_email_rounded,
                  label: user.username,
                  color: const Color(0xFF007AFF),
                ),
              ),
              _buildPill(
                icon: user.role == 'admin'
                    ? Icons.shield_rounded
                    : Icons.person_rounded,
                label: user.role == 'admin' ? 'مسؤول نظام' : 'حساب موظف',
                color: user.role == 'admin'
                    ? const Color(0xFFEA580C)
                    : const Color(0xFF64748B),
              ),
              if (user.branchCode.isNotEmpty)
                _buildPill(
                  icon: Icons.storefront_rounded,
                  label: 'فرع ${user.branchCode}',
                  color: const Color(0xFF9333EA),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Online Status
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline
                      ? const Color(0xFF34C759)
                      : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isOnline
                    ? 'متصل الآن'
                    : (user.lastSeen != null
                        ? 'آخر ظهور ${formatEgyptDateTime(user.lastSeen!)}'
                        : 'غير متصل'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Action Buttons: Edit Info + Change Password
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _showEditProfileModal(context, user),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text(
                    'تعديل البيانات',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showChangePasswordModal(context, user),
                  icon: const Icon(Icons.lock_outline_rounded, size: 16),
                  label: const Text(
                    'كلمة المرور',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 9),
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
    );
  }

  Widget _buildInitialLetter(String name) {
    final letter = name.trim().isNotEmpty
        ? name.trim().characters.first.toUpperCase()
        : 'U';
    return Center(
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w900,
          color: Color(0xFF007AFF),
        ),
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _buildAppleGroup({
    required Color cardColor,
    required Color dividerColor,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dividerColor, width: 0.7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(children.length, (index) {
          if (index == children.length - 1) return children[index];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              children[index],
              Divider(
                height: 0.6,
                thickness: 0.6,
                indent: 60,
                color: dividerColor,
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Apple Menu Tile Widget ───────────────────────────────────────────────────

class _AppleTile extends StatelessWidget {
  const _AppleTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.trailing,
    this.isDestructive = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final bool isDestructive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDestructive
        ? const Color(0xFFFF3B30)
        : (isDark ? Colors.white : const Color(0xFF0F172A));
    final subtitleColor = isDark ? Colors.white54 : const Color(0xFF8E8E93);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isDestructive
                      ? const Color(0xFFFF3B30).withOpacity(0.12)
                      : iconColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: isDestructive
                        ? const Color(0xFFFF3B30)
                        : Colors.white,
                    size: 19,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: isDark ? Colors.white24 : const Color(0xFFB0B0B8),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user});

  final AppUser user;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _jobCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.fullName);
    _jobCtrl = TextEditingController(text: widget.user.jobTitle);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _jobCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'تعديل البيانات الشخصية',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'الاسم الكامل',
                  hintText: 'أدخل اسمك المعروض للزملاء',
                  prefixIcon: const Icon(Icons.person_rounded, size: 20),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'الاسم الكامل مطلوب'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _jobCtrl,
                decoration: InputDecoration(
                  labelText: 'المسمى الوظيفي',
                  hintText: 'مثال: مهندس برمجيات، محاسب، مدير فرع...',
                  prefixIcon: const Icon(Icons.work_outline_rounded, size: 20),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        setState(() => _saving = true);
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(authControllerProvider.notifier)
                              .updateProfile(
                                fullName: _nameCtrl.text.trim(),
                                jobTitle: _jobCtrl.text.trim(),
                              );
                          if (mounted) {
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('تم حفظ البيانات بنجاح'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() => _saving = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text('تعذر الحفظ: $e')),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'حفظ التعديلات',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet({required this.user});

  final AppUser user;

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _confirmCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pwdCtrl = TextEditingController();
    _confirmCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pwdCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'تغيير كلمة المرور',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'أدخل كلمة مرور قوية جديدة لتأمين حسابك',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _pwdCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 6) {
                    return 'يجب أن تكون كلمة المرور 6 أحرف على الأقل';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (v) {
                  if (v != _pwdCtrl.text) {
                    return 'كلمات المرور غير متطابقة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        setState(() => _saving = true);
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(authControllerProvider.notifier)
                              .updateProfile(
                                fullName: widget.user.fullName,
                                password: _pwdCtrl.text.trim(),
                              );
                          if (mounted) {
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('تم تحديث كلمة المرور بنجاح'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() => _saving = false);
                            messenger.showSnackBar(
                              SnackBar(content: Text('تعذر التحديث: $e')),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'تأكيد وتغيير كلمة المرور',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangeServerUrlDialog extends StatefulWidget {
  const _ChangeServerUrlDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ChangeServerUrlDialog> createState() => _ChangeServerUrlDialogState();
}

class _ChangeServerUrlDialogState extends State<_ChangeServerUrlDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'تغيير رابط الخادم (API Base URL)',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: 'عنوان الخادم',
          hintText: 'http://192.168.1.10:5000',
          filled: true,
          fillColor: isDark
              ? const Color(0xFF2C2C2E)
              : const Color(0xFFF2F2F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('__reset__'),
          child: const Text('الافتراضي'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
