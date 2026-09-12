import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';

class MobilePrinterMonitoringScreen extends ConsumerWidget {
  const MobilePrinterMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final canSync = user?.canSyncPrinterModule == true;
    final state = ref.watch(mobilePrinterControllerProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: scaffoldBg,
        appBar: AppBar(
          title: const Text('مراقبة الطابعات'),
          backgroundColor: scaffoldBg,
          scrolledUnderElevation: 0,
          actions: [
            if (canSync)
              IconButton(
                tooltip: 'مزامنة',
                onPressed: () async {
                  try {
                    await ref
                        .read(mobilePrinterControllerProvider.notifier)
                        .fullSync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم تحديث بيانات الطابعات.'),
                        ),
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  }
                },
                icon: const Icon(Icons.sync_rounded),
              ),
          ],
        ),
        body: state.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: const [
                  Expanded(
                    child: ShimmerSkeleton(height: 100, borderRadius: 16),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ShimmerSkeleton(height: 100, borderRadius: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: const [
                  Expanded(
                    child: ShimmerSkeleton(height: 100, borderRadius: 16),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ShimmerSkeleton(height: 100, borderRadius: 16),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const ShimmerSkeleton(width: 120, height: 20, borderRadius: 8),
              const SizedBox(height: 12),
              const ShimmerSkeleton(height: 200, borderRadius: 16),
            ],
          ),
          error: (error, _) => Center(child: Text(error.toString())),
          data: (data) => RefreshIndicator(
            onRefresh: () =>
                ref.read(mobilePrinterControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: 40,
              ),
              children: [
                // Stats Grid
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'الفروع',
                        value: data.totals['branches'] ?? 0,
                        icon: Icons.account_tree_rounded,
                        color: Colors.blue,
                        cardBg: cardBg,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'الطابعات',
                        value: data.totals['printers'] ?? 0,
                        icon: Icons.print_rounded,
                        color: Colors.purple,
                        cardBg: cardBg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'المتصلة',
                        value: data.totals['onlinePrinters'] ?? 0,
                        icon: Icons.wifi_rounded,
                        color: Colors.green,
                        cardBg: cardBg,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        title: 'الهالك',
                        value: data.totals['wastePages'] ?? 0,
                        icon: Icons.delete_sweep_rounded,
                        color: Colors.red,
                        cardBg: cardBg,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),
                const _SectionTitle(title: 'أكثر الطابعات استخداما'),
                const SizedBox(height: 8),
                if (data.printers.isEmpty)
                  _EmptyState(
                    cardBg: cardBg,
                    icon: Icons.print_disabled_rounded,
                    text: 'لا توجد طابعات مسجلة. شغل الاكتشاف من الديسكتوب.',
                  )
                else
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: data.printers.asMap().entries.map((entry) {
                        final isLast = entry.key == data.printers.length - 1;
                        final printer = entry.value;
                        final isOnline =
                            printer['status']?.toString() == 'online';
                        return Column(
                          children: [
                            ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (isOnline ? Colors.green : Colors.grey)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.print_rounded,
                                  color: isOnline ? Colors.green : Colors.grey,
                                ),
                              ),
                              title: Text(
                                printer['printerName']?.toString() ??
                                    printer['ipAddress']?.toString() ??
                                    'طابعة مجهولة',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                '${printer['branchName'] ?? 'بدون فرع'} | ${_status(printer['status'])}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${(printer['lifetimeCounters'] as Map?)?['totalPages'] ?? 0}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    'ورقة',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              const Divider(
                                height: 0.5,
                                thickness: 0.5,
                                indent: 56,
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 28),
                const _SectionTitle(title: 'التنبيهات'),
                const SizedBox(height: 8),
                if (data.notifications.isEmpty)
                  _EmptyState(
                    cardBg: cardBg,
                    icon: Icons.notifications_off_rounded,
                    text: 'لا توجد تنبيهات حالياً.',
                  )
                else
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: data.notifications.asMap().entries.map((entry) {
                        final isLast =
                            entry.key == data.notifications.length - 1;
                        final item = entry.value;
                        return Column(
                          children: [
                            ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.notifications_active_rounded,
                                  color: Colors.orange,
                                ),
                              ),
                              title: Text(
                                item['title']?.toString() ?? 'تنبيه',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                item['message']?.toString() ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (!isLast)
                              const Divider(
                                height: 0.5,
                                thickness: 0.5,
                                indent: 56,
                              ),
                          ],
                        );
                      }).toList(),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, left: 8, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.cardBg,
    required this.icon,
    required this.text,
  });
  final Color cardBg;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.cardBg,
  });

  final String title;
  final num value;
  final IconData icon;
  final Color color;
  final Color cardBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value.toStringAsFixed(0),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

String _status(Object? value) {
  switch (value?.toString()) {
    case 'online':
      return 'متصلة';
    case 'offline':
      return 'غير متصلة';
    default:
      return value?.toString() ?? '';
  }
}
