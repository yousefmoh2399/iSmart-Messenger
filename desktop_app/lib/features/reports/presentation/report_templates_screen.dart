import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/report_template_models.dart';
import 'report_templates_controller.dart';

class ReportTemplatesScreen extends ConsumerStatefulWidget {
  const ReportTemplatesScreen({
    super.key,
    this.initialReportType = 'printer_consumption',
  });

  final String initialReportType;

  @override
  ConsumerState<ReportTemplatesScreen> createState() =>
      _ReportTemplatesScreenState();
}

class _ReportTemplatesScreenState extends ConsumerState<ReportTemplatesScreen> {
  late String _selectedReportType;
  ReportTemplate? _selectedTemplate;
  bool _isEditingNew = false;

  // Controllers for active template fields
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _line1Controller = TextEditingController();
  final _line2Controller = TextEditingController();
  final _line3Controller = TextEditingController();
  final _titleFormatController = TextEditingController();
  final _footerNoteController = TextEditingController();

  bool _isDefault = false;
  bool _showLogo1 = true;
  bool _showLogo2 = true;
  String _orientation = 'landscape';
  bool _includeSummaryRow = true;
  int _rowHeight = 44;
  String _exportFormatDefault = 'xlsx';
  List<ReportColumn> _columns = [];

  int _editorTabIndex = 0; // 0: Columns, 1: Header/Branding, 2: Layout
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedReportType = widget.initialReportType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _line1Controller.dispose();
    _line2Controller.dispose();
    _line3Controller.dispose();
    _titleFormatController.dispose();
    _footerNoteController.dispose();
    super.dispose();
  }

  void _loadTemplateIntoForm(ReportTemplate template, {bool isNew = false}) {
    setState(() {
      _selectedTemplate = isNew ? null : template;
      _isEditingNew = isNew;
      _nameController.text = isNew ? '${template.name} (نسخة معدلة)' : template.name;
      _descriptionController.text = template.description;
      _line1Controller.text = template.headerConfig.line1;
      _line2Controller.text = template.headerConfig.line2;
      _line3Controller.text = template.headerConfig.line3;
      _titleFormatController.text = template.headerConfig.titleFormat;
      _footerNoteController.text = template.headerConfig.footerNote;
      _isDefault = isNew ? false : template.isDefault;
      _showLogo1 = template.headerConfig.showLogo1;
      _showLogo2 = template.headerConfig.showLogo2;
      _orientation = template.options.orientation;
      _includeSummaryRow = template.options.includeSummaryRow;
      _rowHeight = template.options.rowHeight;
      _exportFormatDefault = template.options.exportFormatDefault;
      _columns = template.columns.map((c) => c.copyWith()).toList();
    });
  }

  Future<void> _saveCurrentTemplate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('يجب كتابة اسم للقالب.');
      return;
    }

    final hasEnabledCols = _columns.any((c) => c.enabled);
    if (!hasEnabledCols) {
      _showError('يجب تفعيل عمود واحد على الأقل في التقرير.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final templateToSave = ReportTemplate(
        id: _isEditingNew ? '' : (_selectedTemplate?.id ?? ''),
        name: name,
        reportType: _selectedReportType,
        description: _descriptionController.text.trim(),
        isDefault: _isDefault,
        headerConfig: ReportHeaderConfig(
          line1: _line1Controller.text.trim(),
          line2: _line2Controller.text.trim(),
          line3: _line3Controller.text.trim(),
          titleFormat: _titleFormatController.text.trim(),
          showLogo1: _showLogo1,
          showLogo2: _showLogo2,
          footerNote: _footerNoteController.text.trim(),
        ),
        columns: _columns,
        options: ReportOptions(
          orientation: _orientation,
          includeSummaryRow: _includeSummaryRow,
          rowHeight: _rowHeight,
          exportFormatDefault: _exportFormatDefault,
        ),
      );

      final saved = await ref
          .read(reportTemplateActionControllerProvider.notifier)
          .saveTemplate(templateToSave);

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        if (saved != null) {
          _loadTemplateIntoForm(saved, isNew: false);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم حفظ قالب التقرير بنجاح'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('خطأ أثناء الحفظ: $e');
    }
  }

  Future<void> _deleteTemplate(ReportTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف القالب'),
        content: Text('هل أنت متأكد من حذف القالب "${template.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await ref
          .read(reportTemplateActionControllerProvider.notifier)
          .deleteTemplate(template.id, _selectedReportType);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم حذف القالب'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('خطأ أثناء الحذف: $e');
    }
  }

  Future<void> _setAsDefault(ReportTemplate template) async {
    try {
      await ref
          .read(reportTemplateActionControllerProvider.notifier)
          .setDefault(template.id, _selectedReportType);

      if (!mounted) return;
      setState(() => _isDefault = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('تم تعيين القالب كافتراضي لهذا التقرير'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('خطأ: $e');
    }
  }

  void _showAddColumnPicker(List<ReportColumn> available) {
    final existingKeys = _columns.map((c) => c.key).toSet();
    final remaining = available.where((c) => !existingKeys.contains(c.key)).toList();

    if (remaining.isEmpty) {
      _showError('جميع الأعمدة المتاحة في النظام مضافة بالفعل إلى هذا القالب.');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'اختر عموداً لإضافته إلى التقرير',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.separated(
                itemCount: remaining.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final col = remaining[index];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE0E7FF),
                      child: Icon(Icons.view_column_rounded, color: Color(0xFF4F46E5), size: 20),
                    ),
                    title: Text(col.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(col.description.isNotEmpty ? col.description : col.key),
                    trailing: const Icon(Icons.add_circle_outline_rounded),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _columns.add(
                          col.copyWith(
                            enabled: true,
                            order: _columns.length + 1,
                          ),
                        );
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final templatesAsync = ref.watch(
      reportTemplatesFamilyProvider(_selectedReportType),
    );
    final availableColumnsAsync = ref.watch(
      availableColumnsFamilyProvider(_selectedReportType),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('تخصيص قوالب التقارير (Excel / PDF)'),
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('خطأ: $err')),
        data: (templates) {
          if (_selectedTemplate == null && templates.isNotEmpty && !_isEditingNew) {
            final defaultTpl = templates.firstWhere(
              (t) => t.isDefault,
              orElse: () => templates.first,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedTemplate == null) {
                _loadTemplateIntoForm(defaultTpl);
              }
            });
          }

          return Column(
            children: [
              // 1. Top Type Selector Bar
              _buildTopTypeSegment(theme, isDark),
              const Divider(height: 1),

              // 2. Responsive 2-Column Area
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Right Sidebar: Templates List
                    SizedBox(
                      width: 320,
                      child: _buildTemplatesList(templates, theme, isDark),
                    ),
                    const VerticalDivider(width: 1),

                    // Left Main Panel: Active Template Customizer
                    Expanded(
                      child: availableColumnsAsync.when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('خطأ: $e')),
                        data: (available) => _buildTemplateEditor(
                          available,
                          theme,
                          isDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopTypeSegment(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: isDark ? const Color(0xFF1E1E20) : Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.dashboard_customize_rounded,
              color: Color(0xFF4F46E5),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'محرر ومصمم شكل التقارير',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'اختر نوع التقرير لتعديل أعمدته وترويسته وحفظ قوالب مخصصة',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _TypePill(
                  label: 'استهلاك ورق الطابعات',
                  icon: Icons.print_outlined,
                  isSelected: _selectedReportType == 'printer_consumption',
                  onTap: () {
                    setState(() {
                      _selectedReportType = 'printer_consumption';
                      _selectedTemplate = null;
                      _isEditingNew = false;
                    });
                  },
                ),
                const SizedBox(width: 6),
                _TypePill(
                  label: 'تذاكر الدعم والشكاوى',
                  icon: Icons.confirmation_number_outlined,
                  isSelected: _selectedReportType == 'tickets',
                  onTap: () {
                    setState(() {
                      _selectedReportType = 'tickets';
                      _selectedTemplate = null;
                      _isEditingNew = false;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatesList(
    List<ReportTemplate> templates,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
      color: isDark ? const Color(0xFF19191B) : const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text(
                  'القوالب المحفوظة (${templates.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    final base = _selectedTemplate ?? (templates.isNotEmpty ? templates.first : null);
                    if (base != null) {
                      _loadTemplateIntoForm(base, isNew: true);
                    }
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('قالب جديد'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: templates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final t = templates[index];
                final isSelected = !_isEditingNew && _selectedTemplate?.id == t.id;

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _loadTemplateIntoForm(t),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFEEF2FF))
                          : (isDark
                              ? const Color(0xFF202022)
                              : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF4F46E5)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.06)),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: isSelected ? const Color(0xFF4F46E5) : null,
                                ),
                              ),
                            ),
                            if (t.isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'افتراضي',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (t.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            t.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.view_column_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${t.columns.where((c) => c.enabled).length} عمود مفعل',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11.5,
                              ),
                            ),
                            const Spacer(),
                            if (!t.isDefault)
                              IconButton(
                                tooltip: 'تعيين كافتراضي',
                                icon: const Icon(Icons.star_outline_rounded, size: 18),
                                onPressed: () => _setAsDefault(t),
                              ),
                            if (templates.length > 1)
                              IconButton(
                                tooltip: 'حذف',
                                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                onPressed: () => _deleteTemplate(t),
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
        ],
      ),
    );
  }

  Widget _buildTemplateEditor(
    List<ReportColumn> available,
    ThemeData theme,
    bool isDark,
  ) {
    return Container(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      child: Column(
        children: [
          // Sub-header with Tab Bar & Save Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _SubTabPill(
                        label: 'الأعمدة والمسميات (${_columns.where((c) => c.enabled).length})',
                        icon: Icons.table_chart_outlined,
                        isSelected: _editorTabIndex == 0,
                        onTap: () => setState(() => _editorTabIndex = 0),
                      ),
                      const SizedBox(width: 8),
                      _SubTabPill(
                        label: 'الترويسة والشعار والخطوط',
                        icon: Icons.title_rounded,
                        isSelected: _editorTabIndex == 1,
                        onTap: () => setState(() => _editorTabIndex = 1),
                      ),
                      const SizedBox(width: 8),
                      _SubTabPill(
                        label: 'خيارات التنسيق والصفحة',
                        icon: Icons.tune_rounded,
                        isSelected: _editorTabIndex == 2,
                        onTap: () => setState(() => _editorTabIndex = 2),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveCurrentTemplate,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _isSaving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Editor Content Body
          Expanded(
            child: IndexedStack(
              index: _editorTabIndex,
              children: [
                _buildColumnsTab(available, theme, isDark),
                _buildHeaderBrandingTab(theme, isDark),
                _buildLayoutOptionsTab(theme, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnsTab(
    List<ReportColumn> available,
    ThemeData theme,
    bool isDark,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: isDark ? const Color(0xFF222224) : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              const SizedBox(width: 48, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(width: 44, child: Text('تفعيل', style: TextStyle(fontWeight: FontWeight.bold))),
              const Expanded(
                flex: 4,
                child: Text('مسمى العمود في التقرير (قابل للتعديل)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              const Expanded(
                flex: 3,
                child: Text('المعرف البرمجي / الوصف', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 100, child: Text('الترتيب', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(width: 44),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _columns.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _columns.removeAt(oldIndex);
                _columns.insert(newIndex, item);
                for (int i = 0; i < _columns.length; i++) {
                  _columns[i] = _columns[i].copyWith(order: i + 1);
                }
              });
            },
            itemBuilder: (context, index) {
              final col = _columns[index];

              return Container(
                key: ValueKey(col.key),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const SizedBox(
                        width: 48,
                        child: Icon(Icons.drag_indicator_rounded, color: Colors.grey),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Checkbox(
                        value: col.enabled,
                        onChanged: (val) {
                          setState(() {
                            _columns[index] = col.copyWith(enabled: val == true);
                          });
                        },
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: TextFormField(
                        initialValue: col.label,
                        style: TextStyle(
                          fontWeight: col.enabled ? FontWeight.bold : FontWeight.normal,
                          color: col.enabled ? null : Colors.grey,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) {
                          _columns[index] = col.copyWith(label: val.trim());
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: Text(
                        col.description.isNotEmpty ? col.description : col.key,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                            onPressed: index > 0
                                ? () {
                                    setState(() {
                                      final item = _columns.removeAt(index);
                                      _columns.insert(index - 1, item);
                                    });
                                  }
                                : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                            onPressed: index < _columns.length - 1
                                ? () {
                                    setState(() {
                                      final item = _columns.removeAt(index);
                                      _columns.insert(index + 1, item);
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                        tooltip: 'إزالة من القالب',
                        onPressed: () {
                          setState(() {
                            _columns.removeAt(index);
                          });
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _showAddColumnPicker(available),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة عمود إضافي من بيانات النظام...'),
              ),
              const Spacer(),
              Text(
                'يمكنك سحب أي عمود لتغيير موضعه، أو تعديل اسمه بالضغط المباشر على الحقل.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBrandingTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'بيانات واسم القالب',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم القالب',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'وصف القالب (اختياري)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _isDefault,
            onChanged: (val) => setState(() => _isDefault = val),
            title: const Text('تعيين كقالب معتمد افتراضي لهذا التقرير'),
            subtitle: const Text('سيتم تصدير التقارير تلقائياً بهذا الشكل لجميع المستخدمين ما لم يتم اختيار قالب آخر'),
          ),
          const Divider(height: 32),
          Text(
            'بيانات وهوية الترويسة الرسمية (Header)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'هذه السطور تظهر في أعلى صفحة التقرير في ملفات PDF والإكسل',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _line1Controller,
            decoration: const InputDecoration(
              labelText: 'السطر الأول (الجهة / المؤسسة)',
              hintText: 'جمعية رجال الأعمال والمستثمرين بالدقهلية',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _line2Controller,
            decoration: const InputDecoration(
              labelText: 'السطر الثاني (المشروع / الإدارة)',
              hintText: 'مشروع تنمية المنشآت الصغيرة والحرفية',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.corporate_fare_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _line3Controller,
            decoration: const InputDecoration(
              labelText: 'السطر الثالث (الترخيص / السجل / الإشهار)',
              hintText: 'رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleFormatController,
            decoration: const InputDecoration(
              labelText: 'صيغة العنوان الرئيسي للتقرير',
              hintText: 'استهلاك {entity} للورق عن شهر {month} {year}',
              helperText: 'يمكنك استخدام المتغيرات: {month} للشهر، {year} للسنة، {entity} لاسم الفرع أو الفروع',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.format_size_rounded),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _showLogo1,
                  onChanged: (val) => setState(() => _showLogo1 = val == true),
                  title: const Text('إظهار الشعار الأيمن'),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _showLogo2,
                  onChanged: (val) => setState(() => _showLogo2 = val == true),
                  title: const Text('إظهار الشعار الأيسر'),
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Text(
            'تذييل التقرير والملاحظات (Footer)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _footerNoteController,
            decoration: const InputDecoration(
              labelText: 'توقيع أو اعتماد أسفل التقرير',
              hintText: 'يعتمد، مدير تكنولوجيا المعلومات',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.draw_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutOptionsTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اتجاه صفحة التقرير في PDF',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'landscape',
                icon: Icon(Icons.panorama_horizontal_outlined),
                label: Text('عرضي (Landscape) - موصى به للجداول'),
              ),
              ButtonSegment(
                value: 'portrait',
                icon: Icon(Icons.panorama_vertical_outlined),
                label: Text('طولي (Portrait)'),
              ),
            ],
            selected: {_orientation},
            onSelectionChanged: (val) => setState(() => _orientation = val.first),
          ),
          const Divider(height: 32),
          Text(
            'إحصائيات وإجماليات التقرير',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _includeSummaryRow,
            onChanged: (val) => setState(() => _includeSummaryRow = val),
            title: const Text('تضمين صف الإجماليات (Totals Row) أسفل الجدول'),
            subtitle: const Text('يقوم بحساب وجمع إجمالي الصفحات، الرزم، الهالك، الأعداد تلقائياً في نهاية التقرير'),
          ),
          const Divider(height: 32),
          Text(
            'الصيغة الافتراضية المفضلة عند التصدير',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
            selected: {_exportFormatDefault},
            onSelectionChanged: (val) => setState(() => _exportFormatDefault = val.first),
          ),
        ],
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F46E5) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
                color: isSelected ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubTabPill extends StatelessWidget {
  const _SubTabPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4F46E5).withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF4F46E5) : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
                color: isSelected ? const Color(0xFF4F46E5) : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
