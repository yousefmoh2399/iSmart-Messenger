import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import 'report_templates_controller.dart';
import 'report_templates_screen.dart';

class CustomReportExportDialog extends ConsumerStatefulWidget {
  const CustomReportExportDialog({
    super.key,
    required this.reportType,
    required this.title,
    this.initialFormat = 'xlsx',
  });

  final String reportType;
  final String title;
  final String initialFormat;

  static Future<({String format, String? templateId})?> show({
    required BuildContext context,
    required String reportType,
    required String title,
    String initialFormat = 'xlsx',
  }) {
    return showDialog<({String format, String? templateId})>(
      context: context,
      builder: (_) => CustomReportExportDialog(
        reportType: reportType,
        title: title,
        initialFormat: initialFormat,
      ),
    );
  }

  @override
  ConsumerState<CustomReportExportDialog> createState() =>
      _CustomReportExportDialogState();
}

class _CustomReportExportDialogState
    extends ConsumerState<CustomReportExportDialog> {
  late String _format;
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _format = widget.initialFormat;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authUser = ref.watch(authControllerProvider).valueOrNull;
    final isAdmin = authUser?.role == 'admin';

    final templatesAsync = ref.watch(
      reportTemplatesFamilyProvider(widget.reportType),
    );

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.all(24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.file_download_outlined,
              color: Color(0xFF4F46E5),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'صيغة الملف:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'xlsx',
                  icon: Icon(Icons.table_chart_rounded, color: Colors.green),
                  label: Text('Excel (.xlsx)'),
                ),
                ButtonSegment(
                  value: 'pdf',
                  icon: Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                  label: Text('PDF (.pdf)'),
                ),
              ],
              selected: {_format},
              onSelectionChanged: (val) => setState(() => _format = val.first),
            ),
            const SizedBox(height: 20),
            const Text(
              'شكل وقالب التقرير:',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            templatesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('خطأ في جلب القوالب: $err'),
              data: (templates) {
                if (templates.isEmpty) {
                  return const Text('لا توجد قوالب متاحة، سيتم استخدام التنسيق الافتراضي.');
                }

                if (_selectedTemplateId == null) {
                  final defaultTpl = templates.firstWhere(
                    (t) => t.isDefault,
                    orElse: () => templates.first,
                  );
                  _selectedTemplateId = defaultTpl.id;
                }

                return DropdownButtonFormField<String>(
                  value: _selectedTemplateId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: templates.map((t) {
                    return DropdownMenuItem<String>(
                      value: t.id,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (t.isDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'افتراضي',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTemplateId = val);
                  },
                );
              },
            ),
            if (isAdmin) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportTemplatesScreen(
                          initialReportType: widget.reportType,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                  label: const Text('تخصيص وتعديل الأعمدة والقوالب...'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () {
            Navigator.pop(context, (format: _format, templateId: _selectedTemplateId));
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('تصدير الآن', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
