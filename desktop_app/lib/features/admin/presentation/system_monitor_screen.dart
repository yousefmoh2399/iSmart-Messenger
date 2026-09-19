import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'system_monitor_controller.dart';


class SystemMonitorScreen extends ConsumerWidget {
  const SystemMonitorScreen({
    super.key,
    this.isWrapped = false,
  });

  final bool isWrapped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(systemMonitorControllerProvider);
    final notifier = ref.read(systemMonitorControllerProvider.notifier);

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('مراقبة النظام'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              notifier.refreshSessions();
              notifier.loadErrors();
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Left side: Users/Sessions Table
          Expanded(
            flex: 2,
            child: Column(
              children: [
                _buildFiltersRow(state, notifier),
                Expanded(
                  child: state.isLoadingSessions && state.sessions.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _buildSessionsTable(context, state, notifier),
                ),
                if (state.sessionsHasMore)
                  TextButton(
                    onPressed: notifier.loadMoreSessions,
                    child: state.isLoadingSessions
                        ? const CircularProgressIndicator()
                        : const Text('تحميل المزيد'),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Right side: Errors Panel
          Expanded(
            flex: 1,
            child: Column(
              children: [
                AppBar(
                  title: const Text('المشاكل والأخطاء'),
                  automaticallyImplyLeading: false,
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                ),
                Expanded(
                  child: state.isLoadingErrors && state.errors.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : _buildErrorsList(context, state, notifier),
                ),
                if (state.errorsHasMore)
                  TextButton(
                    onPressed: notifier.loadMoreErrors,
                    child: state.isLoadingErrors
                        ? const CircularProgressIndicator()
                        : const Text('تحميل المزيد'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return isWrapped
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: scaffold,
          )
        : scaffold;
  }

  Widget _buildFiltersRow(SystemMonitorState state, SystemMonitorController notifier) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'بحث باسم المستخدم...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                notifier.setFilters(search: val);
              },
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: state.statusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('الكل')),
              DropdownMenuItem(value: 'online', child: Text('متصل')),
              DropdownMenuItem(value: 'offline', child: Text('غير متصل')),
            ],
            onChanged: (val) {
              if (val != null) notifier.setFilters(status: val);
            },
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: state.clientTypeFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('جميع الأجهزة')),
              DropdownMenuItem(value: 'desktop', child: Text('كمبيوتر')),
              DropdownMenuItem(value: 'mobile', child: Text('موبايل')),
              DropdownMenuItem(value: 'web', child: Text('ويب')),
            ],
            onChanged: (val) {
              if (val != null) notifier.setFilters(clientType: val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsTable(BuildContext context, SystemMonitorState state, SystemMonitorController notifier) {
    return ListView(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: const [
              DataColumn(label: Text('المستخدم')),
              DataColumn(label: Text('الحالة')),
              DataColumn(label: Text('IP')),
              DataColumn(label: Text('الجهاز')),
              DataColumn(label: Text('نظام التشغيل')),
              DataColumn(label: Text('آخر ظهور')),
            ],
            rows: state.sessions.map((session) {
              return DataRow(
                onSelectChanged: (_) {
                  notifier.loadErrors(sessionId: session.id);
                },
                cells: [
                  DataCell(Text(session.fullName)),
                  DataCell(
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          color: session.isOnline ? Colors.green : Colors.red,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(session.isOnline ? 'متصل' : 'غير متصل'),
                      ],
                    ),
                  ),
                  DataCell(Text(session.ipAddress ?? 'غير متوفر')),
                  DataCell(Text(session.clientType)),
                  DataCell(Text(session.deviceInfo['os']?.toString() ?? 'غير معروف')),
                  DataCell(Text(session.lastSeenAt.toString().split('.')[0])),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorsList(BuildContext context, SystemMonitorState state, SystemMonitorController notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الأخطاء المسجلة (${state.errors.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (state.errors.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('تأكيد الحذف'),
                        content: const Text('هل أنت متأكد من حذف جميع الأخطاء المسجلة؟'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              notifier.deleteAllErrors();
                            },
                            child: const Text('حذف', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('مسح الكل', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
        Expanded(
          child: state.errors.isEmpty
              ? const Center(child: Text('لا توجد أخطاء مسجلة'))
              : ListView.builder(
                  itemCount: state.errors.length,
                  itemBuilder: (context, index) {
                    final error = state.errors[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: error.resolved ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                      child: ExpansionTile(
                        title: Text(error.errorMessage, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${error.username ?? 'مجهول'} • ${error.clientType} • ${error.createdAt.toString().split('.')[0]}'),
                        trailing: IconButton(
                          icon: Icon(
                            error.resolved ? Icons.check_circle : Icons.error,
                            color: error.resolved ? Colors.green : Colors.red,
                          ),
                          onPressed: () {
                            if (!error.resolved) {
                              notifier.resolveError(error.id);
                            }
                          },
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('Context:', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(error.errorContext.toString()),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('StackTrace:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    TextButton.icon(
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: error.stackTrace ?? 'No stack trace'));
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الخطأ')));
                                      },
                                      icon: const Icon(Icons.copy, size: 16),
                                      label: const Text('نسخ الخطأ'),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  color: Colors.black.withOpacity(0.05),
                                  child: SelectableText(error.stackTrace ?? 'No stack trace available'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
