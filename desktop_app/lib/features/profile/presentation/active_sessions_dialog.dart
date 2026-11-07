import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/providers/providers.dart';
import '../../auth/data/auth_repository.dart';

Future<void> showDesktopActiveSessionsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const DesktopActiveSessionsDialog(),
  );
}

class DesktopActiveSessionsDialog extends ConsumerStatefulWidget {
  const DesktopActiveSessionsDialog({super.key});

  @override
  ConsumerState<DesktopActiveSessionsDialog> createState() =>
      _DesktopActiveSessionsDialogState();
}

class _DesktopActiveSessionsDialogState
    extends ConsumerState<DesktopActiveSessionsDialog> {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إنهاء جلسة الجهاز؟'),
          content: Text(
            'سيتم تسجيل الخروج فوراً من «${session.deviceName}» وإبطال صلاحية وصوله إلى حسابك.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
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

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(authRepositoryProvider).revokeSession(session.deviceUid);
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('تم تسجيل الخروج من «${session.deviceName}» بنجاح'),
        ),
      );
      await _loadSessions(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text('تعذر إنهاء الجلسة: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _revokingDeviceUids.remove(session.deviceUid);
        });
      }
    }
  }

  Future<void> _confirmRevokeOtherSessions(int otherCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تسجيل الخروج من جميع الأجهزة الأخرى؟'),
          content: Text(
            'سيتم إنهاء جميع الجلسات النشطة الأخرى ($otherCount ${otherCount == 1 ? 'جهاز' : 'أجهزة'}) فوراً، وسيبقى حسابك مفتوحاً على هذا الكمبيوتر فقط.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
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

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final revokedCount = await ref
          .read(authRepositoryProvider)
          .revokeOtherSessions();
      if (!mounted) return;
      messenger?.showSnackBar(
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
      messenger?.showSnackBar(
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
    return 'آخر نشاط ${formatEgyptDateTime(dateTime)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E242B) : Colors.white;
    final cardColor = isDark
        ? const Color(0xFF28303A)
        : const Color(0xFFF8FAFC);
    final borderColor = isDark ? Colors.white12 : const Color(0xFFE2E8F0);
    final subColor = isDark ? Colors.white60 : const Color(0xFF64748B);

    final currentSession = _overview?.currentSession;
    final otherSessions =
        _overview?.otherSessions ?? const <ActiveDeviceSession>[];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.devices_rounded,
                        color: Color(0xFF22C55E),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الأجهزة المتصلة والجلسات النشطة',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'إدارة الأجهزة المسجل الدخول منها حالياً وإنهاء أي جلسة أخرى فوراً',
                            style: TextStyle(fontSize: 12, color: subColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'تحديث القائمة',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _loading ? null : () => _loadSessions(),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFEF4444),
                          size: 40,
                        ),
                        const SizedBox(height: 10),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _loadSessions,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        Text(
                          'هذا الجهاز (الجلسة الحالية)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: subColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (currentSession != null)
                          _buildSessionCard(
                            session: currentSession,
                            cardColor: cardColor,
                            borderColor: borderColor,
                            subColor: subColor,
                          ),
                        if (otherSessions.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _revokingOthers
                                ? null
                                : () => _confirmRevokeOtherSessions(
                                    otherSessions.length,
                                  ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFEF4444)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _revokingOthers
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.logout_rounded, size: 18),
                            label: Text(
                              'تسجيل الخروج من جميع الأجهزة الأخرى (${otherSessions.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          otherSessions.isEmpty
                              ? 'الأجهزة النشطة الأخرى'
                              : 'الأجهزة النشطة الأخرى (${otherSessions.length})',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: subColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (otherSessions.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  size: 36,
                                  color: subColor,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'لا توجد أي أجهزة أخرى متصلة بحسابك حالياً',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'عند تسجيل الدخول من الهاتف أو أي جهاز آخر سيظهر هنا فوراً.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: subColor,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ...otherSessions.map(
                            (session) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _buildSessionCard(
                                session: session,
                                cardColor: cardColor,
                                borderColor: borderColor,
                                subColor: subColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard({
    required ActiveDeviceSession session,
    required Color cardColor,
    required Color borderColor,
    required Color subColor,
  }) {
    final isRevoking = _revokingDeviceUids.contains(session.deviceUid);
    final badgeColor = session.isDesktop
        ? const Color(0xFF5856D6)
        : const Color(0xFF007AFF);
    final metaParts = <String>[
      session.platformDisplayLabel,
      if (session.appVersion != null && session.appVersion!.isNotEmpty)
        'v${session.appVersion}',
      if (session.ipAddress != null && session.ipAddress!.isNotEmpty)
        'IP: ${session.ipAddress}',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              session.isDesktop
                  ? Icons.desktop_windows_rounded
                  : Icons.smartphone_rounded,
              color: badgeColor,
              size: 22,
            ),
          ),
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (session.isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'هذا الجهاز',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  metaParts.join(' • '),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: session.isOnline
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      session.isCurrent
                          ? 'نشط الآن • الجلسة الحالية'
                          : (session.isOnline
                                ? 'متصل الآن'
                                : _formatRelativeActivity(session.lastUsedAt)),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: session.isOnline
                            ? const Color(0xFF22C55E)
                            : subColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!session.isCurrent)
            isRevoking
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton.tonalIcon(
                    onPressed: () => _confirmRevokeSingleSession(session),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(
                        0xFFEF4444,
                      ).withValues(alpha: 0.12),
                      foregroundColor: const Color(0xFFEF4444),
                    ),
                    icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                    label: const Text(
                      'إنهاء الجلسة',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
