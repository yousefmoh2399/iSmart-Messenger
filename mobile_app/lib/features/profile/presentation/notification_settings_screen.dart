import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/settings/user_preferences.dart';
import '../../../shared/providers/providers.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _isSendingTest = false;
  bool _systemPermissionGranted = true;
  bool _checkingPermission = true;

  @override
  void initState() {
    super.initState();
    _checkSystemPermission();
  }

  Future<void> _checkSystemPermission() async {
    try {
      final localService = ref.read(localNotificationServiceProvider);
      final granted = await localService.areNotificationsEnabled();
      if (mounted) {
        setState(() {
          _systemPermissionGranted = granted;
          _checkingPermission = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkingPermission = false);
      }
    }
  }

  Future<void> _handleSendTestNotification() async {
    setState(() => _isSendingTest = true);
    HapticFeedback.mediumImpact();

    try {
      final localService = ref.read(localNotificationServiceProvider);
      await localService.showTestNotification();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تم إرسال إشعارين تجريبيين مجمعين بنجاح! اسحب شريط الإشعارات لرؤية التجميع كواتساب.',
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF34C759),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إرسال الإشعار التجريبي: $e'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingTest = false);
      }
    }
  }

  Future<void> _handleResetDefaults() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'استعادة إعدادات الإشعارات الافتراضية',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'سيتم إعادة تفعيل كافة الإشعارات، وتفعيل تجميع المحادثات كواتساب، وتعيين النغمات والاهتزاز للوضع الافتراضي.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B30),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'إعادة الضبط الآن',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(userPreferencesControllerProvider.notifier)
          .resetNotificationPreferences();
      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت استعادة إعدادات الإشعارات الافتراضية بنجاح!'),
            backgroundColor: Color(0xFF34C759),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final preferencesState = ref.watch(userPreferencesControllerProvider);
    final preferences = preferencesState.valueOrNull ?? UserPreferences.defaults();
    final notifier = ref.read(userPreferencesControllerProvider.notifier);
    final localNotifications = ref.read(localNotificationServiceProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'إعدادات الإشعارات',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── System Permission Warning Banner (if disabled) ──
          if (!_checkingPermission && !_systemPermissionGranted) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFF3B30).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFFF3B30),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الإشعارات معطلة في النظام',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF3B30),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'لن تصلك أي تنبيهات لأن صلاحية إشعارات الهاتف غير مفعلة لهذا التطبيق.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B30),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () async {
                      await openAppSettings();
                    },
                    child: const Text('تفعيل', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ],

          // ── Hero Status Card ──
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: preferences.notificationsEnabled
                    ? (isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFFE0F2FE), const Color(0xFFF0FDF4)])
                    : (isDark
                        ? [const Color(0xFF27272A), const Color(0xFF18181B)]
                        : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)]),
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: preferences.notificationsEnabled
                    ? const Color(0xFF007AFF).withValues(alpha: 0.25)
                    : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: preferences.notificationsEnabled
                            ? const Color(0xFF007AFF).withValues(alpha: 0.18)
                            : (isDark ? Colors.white10 : Colors.black12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        preferences.notificationsEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_rounded,
                        color: preferences.notificationsEnabled
                            ? const Color(0xFF007AFF)
                            : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                preferences.notificationsEnabled
                                    ? 'الإشعارات مفعلة'
                                    : 'الإشعارات معطلة',
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: preferences.notificationsEnabled
                                      ? const Color(0xFF34C759)
                                      : const Color(0xFFFF3B30),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            preferences.notificationsEnabled
                                ? 'يتم استقبال التنبيهات وتجميعها حسب المحادثة'
                                : 'تم كتم جميع التنبيهات الواردة بالكامل',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    CupertinoSwitch(
                      value: preferences.notificationsEnabled,
                      activeTrackColor: const Color(0xFF34C759),
                      onChanged: (val) {
                        notifier.setNotificationsEnabled(val);
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, thickness: 0.6),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'معاينة التجميع على الهاتف:',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: Color(0xFF007AFF), width: 1),
                      ),
                      onPressed: _isSendingTest ? null : _handleSendTestNotification,
                      icon: _isSendingTest
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 14, color: Color(0xFF007AFF)),
                      label: Text(
                        _isSendingTest ? 'جاري الإرسال...' : 'إرسال إشعار تجريبي',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF007AFF),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Section 1: WhatsApp-style Grouping & Advanced ──
          const _AppleSectionHeader(
            title: 'تجميع الإشعارات الذكي (نظام واتساب)',
            icon: Icons.layers_rounded,
          ),
          _AppleInsetGroup(
            child: Column(
              children: [
                _AppleSwitchTile(
                  icon: Icons.splitscreen_rounded,
                  iconColor: const Color(0xFF34C759),
                  title: 'تجميع إشعارات المحادثات',
                  subtitle:
                      'دمج رسائل كل شخص أو جروب في إشعار واحد ذكي قابل للتوسيع بدلاً من تكرار الإشعارات المنفصلة',
                  value: preferences.groupNotificationsByChat,
                  onChanged: (val) {
                    notifier.setGroupNotificationsByChat(val);
                    HapticFeedback.selectionClick();
                  },
                ),
                const _AppleDivider(),
                _AppleSwitchTile(
                  icon: Icons.auto_delete_rounded,
                  iconColor: const Color(0xFF5856D6),
                  title: 'مسح الإشعارات تلقائياً عند فتح الشات',
                  subtitle:
                      'إلغاء تنبيهات المحادثة من شريط الإشعارات فور دخولك إليها مباشرة مثل واتساب',
                  value: preferences.autoClearOnOpen,
                  onChanged: (val) {
                    notifier.setAutoClearOnOpen(val);
                    HapticFeedback.selectionClick();
                  },
                ),
                const _AppleDivider(),
                _AppleSwitchTile(
                  icon: Icons.call_to_action_rounded,
                  iconColor: const Color(0xFF007AFF),
                  title: 'إشعارات أثناء استخدام التطبيق (In-App)',
                  subtitle:
                      'إظهار شريط تنبيه منبثق أعلى الشاشة عند استلام رسالة وأنت داخل التطبيق',
                  value: preferences.inAppBanners,
                  onChanged: (val) {
                    notifier.setInAppBanners(val);
                    HapticFeedback.selectionClick();
                  },
                ),
                const _AppleDivider(),
                _AppleSwitchTile(
                  icon: Icons.add_reaction_rounded,
                  iconColor: const Color(0xFFFF2D55),
                  title: 'إشعارات تفاعلات الرسائل (Reactions)',
                  subtitle:
                      'استلام تنبيه عند تفاعل أحد بالرموز التعبيرية (❤️, 👍) على رسائلك',
                  value: preferences.reactionNotifications,
                  onChanged: (val) {
                    notifier.setReactionNotifications(val);
                    HapticFeedback.selectionClick();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Section 2: Direct Messages (المحادثات المباشرة) ──
          const _AppleSectionHeader(
            title: 'إشعارات المحادثات الفردية',
            icon: Icons.person_rounded,
          ),
          _AppleInsetGroup(
            child: Column(
              children: [
                _AppleSwitchTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  iconColor: const Color(0xFF007AFF),
                  title: 'تفعيل إشعارات الرسائل الفردية',
                  subtitle: 'استلام تنبيهات للرسائل المباشرة بينك وبين الزملاء',
                  value: preferences.messageNotificationsEnabled,
                  onChanged: (val) {
                    notifier.setMessageNotificationsEnabled(val);
                    HapticFeedback.selectionClick();
                  },
                ),
                const _AppleDivider(),
                _AppleTonePickerTile(
                  icon: Icons.music_note_rounded,
                  iconColor: const Color(0xFFFF9500),
                  title: 'نغمة رسائل المحادثات',
                  selectedToneId: preferences.messageToneId,
                  onToneChanged: (toneId) {
                    notifier.setNotificationTone(toneId);
                    localNotifications.previewNotificationTone(toneId);
                    ref
                        .read(pushNotificationServiceProvider)
                        .registerForAuthenticatedUser();
                  },
                  onPreviewTone: () {
                    localNotifications.previewNotificationTone(
                      preferences.messageToneId,
                    );
                  },
                ),
                const _AppleDivider(),
                _AppleSwitchTile(
                  icon: Icons.vibration_rounded,
                  iconColor: const Color(0xFFAF52DE),
                  title: 'الاهتزاز',
                  subtitle: 'اهتزاز الهاتف عند وصول رسالة فردية جديدة',
                  value: preferences.messageVibrate,
                  onChanged: (val) {
                    notifier.setMessageVibrate(val);
                    HapticFeedback.selectionClick();
                  },
                ),
                const _AppleDivider(),
                _AppleSwitchTile(
                  icon: Icons.visibility_rounded,
                  iconColor: const Color(0xFF34C759),
                  title: 'معاينة محتوى الرسالة',
                  subtitle:
                      'إظهار اسم المرسل ونص الرسالة في الإشعار (عطله للخصوصية التامة)',
                  value: preferences.messagePreview,
                  onChanged: (val) {
                    notifier.setMessagePreview(val);
                    HapticFeedback.selectionClick();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Section 3: Group Chats (المجموعات) ──
          const _AppleSectionHeader(
            title: 'إشعارات المجموعات (جروبات العمل)',
            icon: Icons.groups_rounded,
          ),
          _AppleInsetGroup(
            child: Column(
              children: [
                _AppleSwitchTile(
                  icon: Icons.group_outlined,
                  iconColor: const Color(0xFF5856D6),
                  title: 'تفعيل إشعارات المجموعات',
                  subtitle: 'استلام تنبيهات للرسائل الواردة في المجموعات المشترك بها',
                  value: preferences.groupNotificationsEnabled,
                  onChanged: (val) {
                    notifier.setGroupNotificationsEnabled(val);
                    HapticFeedback.selectionClick();
                  },
                ),
                const _AppleDivider(),
                _AppleTonePickerTile(
                  icon: Icons.music_note_rounded,
                  iconColor: const Color(0xFFFF9500),
                  title: 'نغمة إشعارات المجموعات',
                  selectedToneId: preferences.groupToneId,
                  onToneChanged: (toneId) {
                    notifier.setGroupTone(toneId);
                    localNotifications.previewNotificationTone(toneId);
                  },
                  onPreviewTone: () {
                    localNotifications.previewNotificationTone(
                      preferences.groupToneId,
                    );
                  },
                ),
                const _AppleDivider(),
                _AppleSwitchTile(
                  icon: Icons.vibration_rounded,
                  iconColor: const Color(0xFFAF52DE),
                  title: 'اهتزاز المجموعات',
                  subtitle: 'اهتزاز الهاتف عند استلام رسائل المجموعات',
                  value: preferences.groupVibrate,
                  onChanged: (val) {
                    notifier.setGroupVibrate(val);
                    HapticFeedback.selectionClick();
                  },
                ),
                const _AppleDivider(),
                _AppleSwitchTile(
                  icon: Icons.visibility_rounded,
                  iconColor: const Color(0xFF34C759),
                  title: 'معاينة رسائل المجموعات',
                  subtitle: 'عرض اسم المجموعة والمرسل ونص الرسالة في الإشعار',
                  value: preferences.groupPreview,
                  onChanged: (val) {
                    notifier.setGroupPreview(val);
                    HapticFeedback.selectionClick();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Section 4: System & Reset ──
          const _AppleSectionHeader(
            title: 'إدارة وإعادة الضبط',
            icon: Icons.settings_applications_rounded,
          ),
          _AppleInsetGroup(
            child: Column(
              children: [
                _AppleNavTile(
                  icon: Icons.tune_rounded,
                  iconColor: const Color(0xFF007AFF),
                  title: 'فتح إعدادات إشعارات النظام',
                  subtitle: 'التحكم في ظهور الإشعارات على شاشة القفل والأولويات من أندرويد',
                  onTap: () async {
                    await openAppSettings();
                  },
                ),
                const _AppleDivider(),
                _AppleNavTile(
                  icon: Icons.restart_alt_rounded,
                  iconColor: const Color(0xFFFF3B30),
                  title: 'استعادة إعدادات الإشعارات الافتراضية',
                  subtitle: 'إعادة ضبط كافة خيارات التنبيهات والنغمات والتجميع للوضع الأصلي',
                  onTap: _handleResetDefaults,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Reusable Apple-minimalist components
// ─────────────────────────────────────────────────────────────

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

class _AppleSwitchTile extends StatelessWidget {
  const _AppleSwitchTile({
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          const SizedBox(width: 8),
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

class _AppleTonePickerTile extends StatelessWidget {
  const _AppleTonePickerTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.selectedToneId,
    required this.onToneChanged,
    required this.onPreviewTone,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String selectedToneId;
  final ValueChanged<String> onToneChanged;
  final VoidCallback onPreviewTone;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF007AFF), size: 24),
            tooltip: 'تشغيل النغمة',
            onPressed: onPreviewTone,
          ),
          DropdownButton<String>(
            value: selectedToneId,
            underline: const SizedBox(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            borderRadius: BorderRadius.circular(12),
            dropdownColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            items: NotificationTone.values
                .map(
                  (tone) => DropdownMenuItem(
                    value: tone.id,
                    child: Text(
                      tone.label,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) {
                onToneChanged(val);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _AppleNavTile extends StatelessWidget {
  const _AppleNavTile({
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: iconColor == const Color(0xFFFF3B30)
                            ? const Color(0xFFFF3B30)
                            : (isDark ? Colors.white : const Color(0xFF0F172A)),
                      ),
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
                Icons.chevron_left_rounded,
                size: 20,
                color: isDark ? Colors.white30 : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
