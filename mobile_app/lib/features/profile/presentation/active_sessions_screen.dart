import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../../auth/data/auth_repository.dart';

class ActiveSessionsScreen extends ConsumerStatefulWidget {
  const ActiveSessionsScreen({super.key});

  @override
  ConsumerState<ActiveSessionsScreen> createState() =>
      _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends ConsumerState<ActiveSessionsScreen> {
  ActiveSessionsOverview? _overview;
  bool _loading = true;
  bool _revokingOthers = false;
  final Set<String> _revokingDeviceUids = <String>{};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .fetchActiveSessions();
      if (!mounted) return;
      setState(() {
        _overview = result;
        _loading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _confirmRevokeSingleSession(ActiveDeviceSession session) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: CupertinoAlertDialog(
          title: const Text('إنهاء جلسة الجهاز؟'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'سيتم تسجيل الخروج فوراً من «${session.deviceName}» وإبطال صلاحية وصوله إلى حسابك.',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('إنهاء الجلسة'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _revokingDeviceUids.add(session.deviceUid);
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authRepositoryProvider)
          .revokeSession(session.deviceUid);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      messenger.showSnackBar(
        SnackBar(
          content: Text('تم تسجيل الخروج من «${session.deviceName}» بنجاح'),
        ),
      );
      await _loadSessions(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إنهاء الجلسة: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _revokingDeviceUids.remove(session.deviceUid);
        });
      }
    }
  }

  Future<void> _confirmRevokeOtherSessions(int otherCount) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: CupertinoAlertDialog(
          title: const Text('تسجيل الخروج من الأجهزة الأخرى؟'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'سيتم إنهاء جميع الجلسات النشطة الأخرى ($otherCount ${otherCount == 1 ? 'جهاز' : 'أجهزة'}) فوراً، وسيبقى حسابك مفتوحاً على هذا الجهاز فقط.',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تسجيل الخروج من الباقي'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _revokingOthers = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final revokedCount = await ref
          .read(authRepositoryProvider)
          .revokeOtherSessions();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            revokedCount > 0
                ? 'تم تسجيل الخروج من $revokedCount ${revokedCount == 1 ? 'جهاز آخر' : 'أجهزة أخرى'} بنجاح'
                : 'تم إنهاء جميع الجلسات الأخرى بنجاح',
          ),
        ),
      );
      await _loadSessions(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر إنهاء الجلسات الأخرى: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _revokingOthers = false;
        });
      }
    }
  }

  void _showSessionDetailsSheet(ActiveDeviceSession session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: _buildPlatformAvatar(session, size: 64, iconSize: 32),
              ),
              const SizedBox(height: 12),
              Text(
                session.deviceName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: session.isOnline
                          ? const Color(0xFF34C759)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    session.isCurrent
                        ? 'متصل الآن • هذا الجهاز'
                        : (session.isOnline
                              ? 'متصل الآن'
                              : _formatRelativeActivity(session.lastUsedAt)),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: session.isOnline
                          ? const Color(0xFF34C759)
                          : subColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2C2C2E).withValues(alpha: 0.65)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _buildDetailRow(
                      label: 'النظام والمنصة',
                      value: session.platformDisplayLabel,
                      isDark: isDark,
                    ),
                    const Divider(height: 18, thickness: 0.5),
                    _buildDetailRow(
                      label: 'إصدار التطبيق',
                      value: session.appVersion != null &&
                              session.appVersion!.isNotEmpty
                          ? 'iSmart v${session.appVersion}'
                          : 'iSmart Messenger',
                      isDark: isDark,
                    ),
                    if (session.ipAddress != null &&
                        session.ipAddress!.isNotEmpty) ...[
                      const Divider(height: 18, thickness: 0.5),
                      _buildDetailRow(
                        label: 'عنوان الشبكة (IP)',
                        value: session.ipAddress!,
                        isDark: isDark,
                      ),
                    ],
                    const Divider(height: 18, thickness: 0.5),
                    _buildDetailRow(
                      label: 'تاريخ تسجيل الدخول',
                      value: formatEgyptDateTime(session.createdAt),
                      isDark: isDark,
                    ),
                    const Divider(height: 18, thickness: 0.5),
                    _buildDetailRow(
                      label: 'آخر نشاط مسجّل',
                      value: session.isCurrent
                          ? 'الآن (نشط)'
                          : formatEgyptDateTime(session.lastUsedAt),
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              if (!session.isCurrent) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _confirmRevokeSingleSession(session);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(CupertinoIcons.power, size: 18),
                  label: const Text(
                    'تسجيل الخروج من هذا الجهاز فوراً',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white60 : const Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  String _formatRelativeActivity(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 90) {
      return 'نشط منذ لحظات';
    }
    if (diff.inMinutes < 60) {
      final mins = diff.inMinutes;
      return 'آخر نشاط منذ $mins ${mins == 1 || mins > 10 ? 'دقيقة' : 'دقائق'}';
    }
    if (diff.inHours < 24) {
      final hrs = diff.inHours;
      return 'آخر نشاط منذ $hrs ${hrs == 1 || hrs > 10 ? 'ساعة' : 'ساعات'}';
    }
    if (diff.inDays < 7) {
      final days = diff.inDays;
      return 'آخر نشاط منذ $days ${days == 1 ? 'يوم' : 'أيام'}';
    }
    return 'آخر نشاط ${formatEgyptDateTime(dateTime)}';
  }

  Widget _buildPlatformAvatar(
    ActiveDeviceSession session, {
    double size = 46,
    double iconSize = 23,
  }) {
    final Color badgeColor;
    final IconData iconData;

    switch (session.platform.toLowerCase()) {
      case 'windows':
      case 'macos':
      case 'linux':
        badgeColor = const Color(0xFF5856D6);
        iconData = CupertinoIcons.desktopcomputer;
        break;
      case 'ios':
        badgeColor = const Color(0xFF007AFF);
        iconData = CupertinoIcons.device_phone_portrait;
        break;
      case 'web':
        badgeColor = const Color(0xFF00C7BE);
        iconData = CupertinoIcons.globe;
        break;
      case 'android':
      default:
        badgeColor = session.isCurrent
            ? const Color(0xFF34C759)
            : const Color(0xFF007AFF);
        iconData = CupertinoIcons.device_phone_portrait;
        break;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                badgeColor.withValues(alpha: 0.92),
                badgeColor,
              ],
            ),
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: Icon(iconData, color: Colors.white, size: iconSize),
        ),
        if (session.isOnline)
          PositionedDirectional(
            bottom: -2,
            end: -2,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF1C1C1E)
                      : Colors.white,
                  width: 2.2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final dividerColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFE5E5EA);
    final subtitleColor = isDark ? Colors.white54 : const Color(0xFF64748B);

    final currentSession = _overview?.currentSession;
    final otherSessions =
        _overview?.otherSessions ?? const <ActiveDeviceSession>[];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          backgroundColor: scaffoldBg,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: const Text(
            'الأجهزة المتصلة والجلسات',
            style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.refresh, size: 20),
              tooltip: 'تحديث القائمة',
              onPressed: _loading ? null : () => _loadSessions(),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CupertinoActivityIndicator(radius: 15))
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_shield,
                        size: 46,
                        color: Color(0xFFFF3B30),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadSessions,
                        icon: const Icon(CupertinoIcons.refresh, size: 17),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _loadSessions(silent: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
                  children: [
                    // ── Hero Security Header ─────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: dividerColor, width: 0.7),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF007AFF,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              CupertinoIcons.device_laptop,
                              color: Color(0xFF007AFF),
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'إدارة الأجهزة المتصلة بحسابك',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'يمكنك فتح حسابك على الهاتف وكمبيوتر المكتب في نفس الوقت، وإنهاء جلسة أي جهاز آخر فوراً بضغطة واحدة.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: subtitleColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Current Device Section ───────────────────────────────
                    _buildSectionHeader('هذا الجهاز (الجلسة الحالية)', isDark),
                    Container(
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: dividerColor, width: 0.7),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          if (currentSession != null)
                            _buildSessionTile(
                              session: currentSession,
                              isDark: isDark,
                              subtitleColor: subtitleColor,
                            ),
                          Divider(
                            height: 0.7,
                            thickness: 0.7,
                            color: dividerColor,
                          ),
                          if (otherSessions.isNotEmpty)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _revokingOthers
                                    ? null
                                    : () => _confirmRevokeOtherSessions(
                                        otherSessions.length,
                                      ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13.5,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFFF3B30,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
                                        ),
                                        child: _revokingOthers
                                            ? const Center(
                                                child:
                                                    CupertinoActivityIndicator(
                                                      radius: 9,
                                                    ),
                                              )
                                            : const Icon(
                                                CupertinoIcons.xmark_shield_fill,
                                                color: Color(0xFFFF3B30),
                                                size: 19,
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'تسجيل الخروج من جميع الأجهزة الأخرى',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFFF3B30),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'إنهاء جميع الجلسات المفتوحة ما عدا هذا الجهاز (${otherSessions.length})',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: subtitleColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    CupertinoIcons.checkmark_shield_fill,
                                    color: Color(0xFF34C759),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'لا توجد أي أجهزة أخرى متصلة بحسابك حالياً',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? Colors.white70
                                            : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ── Other Active Devices Section ─────────────────────────
                    _buildSectionHeader(
                      otherSessions.isEmpty
                          ? 'الأجهزة النشطة الأخرى'
                          : 'الأجهزة النشطة الأخرى (${otherSessions.length})',
                      isDark,
                    ),
                    if (otherSessions.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: dividerColor, width: 0.7),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              CupertinoIcons.lock_shield,
                              size: 36,
                              color: isDark
                                  ? Colors.white38
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'حسابك مفتوح على هذا الجهاز فقط',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'عند تسجيل الدخول من كمبيوتر المكتب Windows أو أي هاتف آخر سيظهر هنا فوراً مع إمكانية التحكم به.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: subtitleColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: dividerColor, width: 0.7),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: List.generate(otherSessions.length, (
                            index,
                          ) {
                            final session = otherSessions[index];
                            final tile = _buildSessionTile(
                              session: session,
                              isDark: isDark,
                              subtitleColor: subtitleColor,
                            );
                            if (index == otherSessions.length - 1) {
                              return tile;
                            }
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                tile,
                                Divider(
                                  height: 0.6,
                                  thickness: 0.6,
                                  indent: 72,
                                  color: dividerColor,
                                ),
                              ],
                            );
                          }),
                        ),
                      ),

                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'ملاحظة أمنية: إذا لاحظت وجود جهاز لا تتعرف عليه ضمن القائمة، اضغط على «إنهاء» بجانبه ثم قم بتغيير كلمة المرور من الملف الشخصي.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: subtitleColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildSessionTile({
    required ActiveDeviceSession session,
    required bool isDark,
    required Color subtitleColor,
  }) {
    final isRevoking = _revokingDeviceUids.contains(session.deviceUid);
    final metaParts = <String>[
      session.platformDisplayLabel,
      if (session.appVersion != null && session.appVersion!.isNotEmpty)
        'v${session.appVersion}',
      if (session.ipAddress != null && session.ipAddress!.isNotEmpty)
        'IP: ${session.ipAddress}',
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showSessionDetailsSheet(session),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildPlatformAvatar(session),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (session.isCurrent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF34C759,
                              ).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'هذا الجهاز',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF34C759),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metaParts.join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6.5,
                          height: 6.5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: session.isOnline
                                ? const Color(0xFF34C759)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            session.isCurrent
                                ? 'نشط الآن • الجلسة الحالية'
                                : (session.isOnline
                                      ? 'متصل الآن'
                                      : _formatRelativeActivity(
                                          session.lastUsedAt,
                                        )),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: session.isOnline
                                  ? const Color(0xFF34C759)
                                  : subtitleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!session.isCurrent) ...[
                const SizedBox(width: 8),
                isRevoking
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: CupertinoActivityIndicator(radius: 10),
                      )
                    : TextButton.icon(
                        onPressed: () => _confirmRevokeSingleSession(session),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF3B30),
                          backgroundColor: const Color(
                            0xFFFF3B30,
                          ).withValues(alpha: 0.10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(CupertinoIcons.power, size: 14),
                        label: const Text(
                          'إنهاء',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ] else
                Icon(
                  Icons.chevron_left_rounded,
                  size: 20,
                  color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
