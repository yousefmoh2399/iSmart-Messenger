import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
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
  final _secondaryNoteController = TextEditingController();
  final _preparedByController = TextEditingController();
  final _approvedByController = TextEditingController();
  final _footerNoteController = TextEditingController();

  bool _isDefault = false;
  bool _showLogo1 = true;
  bool _showLogo2 = true;
  String? _customLogo1;
  String? _customLogo2;
  String _orientation = 'landscape';
  bool _includeSummaryRow = true;
  int _rowHeight = 44;
  String _exportFormatDefault = 'xlsx';
  List<ReportColumn> _columns = [];

  int _editorTabIndex = 0; // 0: Columns, 1: Header/Branding, 2: Layout, 3: Preview
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
    _secondaryNoteController.dispose();
    _preparedByController.dispose();
    _approvedByController.dispose();
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
      _secondaryNoteController.text = template.headerConfig.secondaryNote;
      _preparedByController.text = template.headerConfig.preparedByLabel;
      _approvedByController.text = template.headerConfig.approvedByLabel;
      _footerNoteController.text = template.headerConfig.footerNote;
      _isDefault = isNew ? false : template.isDefault;
      _showLogo1 = template.headerConfig.showLogo1;
      _showLogo2 = template.headerConfig.showLogo2;
      _customLogo1 = template.headerConfig.customLogo1;
      _customLogo2 = template.headerConfig.customLogo2;
      _orientation = template.options.orientation;
      _includeSummaryRow = template.options.includeSummaryRow;
      _rowHeight = template.options.rowHeight;
      _exportFormatDefault = template.options.exportFormatDefault;
      _columns = template.columns.map((c) => c.copyWith()).toList();
    });
  }

  Future<void> _pickCustomLogo(int logoIndex) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر صورة الشعار',
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      List<int>? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        final f = File(file.path!);
        if (await f.exists()) {
          bytes = await f.readAsBytes();
        }
      }

      if (bytes != null) {
        final ext = (file.extension ?? 'png').toLowerCase();
        final mimeType = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';
        final base64Str = 'data:$mimeType;base64,${base64Encode(bytes)}';

        setState(() {
          if (logoIndex == 1) {
            _customLogo1 = base64Str;
            _showLogo1 = true;
          } else {
            _customLogo2 = base64Str;
            _showLogo2 = true;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('تم استبدال الشعار $logoIndex بنجاح'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('تعذر اختيار الصورة: $e');
      }
    }
  }

  void _resetLogo(int logoIndex) {
    setState(() {
      if (logoIndex == 1) {
        _customLogo1 = null;
      } else {
        _customLogo2 = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('تم استعادة الشعار الافتراضي للشعار $logoIndex'),
      ),
    );
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
          customLogo1: _customLogo1,
          customLogo2: _customLogo2,
          secondaryNote: _secondaryNoteController.text.trim(),
          footerNote: _footerNoteController.text.trim(),
          preparedByLabel: _preparedByController.text.trim(),
          approvedByLabel: _approvedByController.text.trim(),
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

  Widget _buildLogoWidget(String? customLogo, bool showLogo, {double size = 64}) {
    if (!showLogo) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: const Center(
          child: Text(
            'شعار مخفي',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    if (customLogo != null && customLogo.isNotEmpty) {
      try {
        if (customLogo.startsWith('data:image')) {
          final comma = customLogo.indexOf(',');
          final base64Data = comma != -1 ? customLogo.substring(comma + 1) : customLogo;
          final bytes = base64Decode(base64Data);
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, width: size, height: size, fit: BoxFit.contain),
          );
        } else if (File(customLogo).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(customLogo), width: size, height: size, fit: BoxFit.contain),
          );
        }
      } catch (_) {}
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/images/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(Icons.corporate_fare_rounded, size: size * 0.7, color: Colors.grey),
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
                'تخصيص شكل التقرير، استبدال الشعارات، إضافة نصوص ثابتة، وتحديد العمليات الحسابية',
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
                  'نماذج وقوالب التقرير',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    final base = templates.isNotEmpty ? templates.first : null;
                    if (base != null) {
                      _loadTemplateIntoForm(base, isNew: true);
                    }
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('قالب جديد', style: TextStyle(fontSize: 12)),
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
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _loadTemplateIntoForm(t, isNew: false),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF4F46E5).withValues(alpha: 0.08)
                          : (isDark ? const Color(0xFF222224) : Colors.white),
                      borderRadius: BorderRadius.circular(12),
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
          // Sub-header with Tab Bar & Save/Preview Buttons
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
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _SubTabPill(
                          label: 'الأعمدة والحسابات (${_columns.where((c) => c.enabled).length})',
                          icon: Icons.table_chart_outlined,
                          isSelected: _editorTabIndex == 0,
                          onTap: () => setState(() => _editorTabIndex = 0),
                        ),
                        const SizedBox(width: 8),
                        _SubTabPill(
                          label: 'الترويسة والشعارات والنصوص',
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
                        const SizedBox(width: 8),
                        _SubTabPill(
                          label: 'معاينة القالب الحية',
                          icon: Icons.visibility_rounded,
                          isSelected: _editorTabIndex == 3,
                          onTap: () => setState(() => _editorTabIndex = 3),
                        ),
                      ],
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: () => setState(() => _editorTabIndex = 3),
                  icon: const Icon(Icons.preview_rounded, size: 18),
                  label: const Text('معاينة حية', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
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
                _buildLiveDocumentPreview(theme, isDark),
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
          child: const Row(
            children: [
              SizedBox(width: 36, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
              SizedBox(width: 44, child: Text('تفعيل', style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                flex: 4,
                child: Text('مسمى العمود في التقرير (قابل للتعديل)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text('العملية الحسابية في الإجمالي', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text('المعرف البرمجي / الوصف', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              SizedBox(width: 80, child: Text('الترتيب', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
              SizedBox(width: 44),
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
                        width: 36,
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
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: ['none', 'sum', 'avg', 'count', 'diff', 'min', 'max'].contains(col.calculationType)
                            ? col.calculationType
                            : 'none',
                        isDense: true,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('بدون عملية حسابية', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(
                            value: 'sum',
                            child: Text('∑ جمع إجمالي (مجموع)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                          ),
                          DropdownMenuItem(
                            value: 'avg',
                            child: Text('∅ متوسط حسابي', style: TextStyle(fontSize: 12, color: Color(0xFF0D9488))),
                          ),
                          DropdownMenuItem(
                            value: 'count',
                            child: Text('# عدد السجلات', style: TextStyle(fontSize: 12, color: Color(0xFFD97706))),
                          ),
                          DropdownMenuItem(
                            value: 'diff',
                            child: Text('− طرح / فرق صافي', style: TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
                          ),
                          DropdownMenuItem(
                            value: 'min',
                            child: Text('↓ أقل قيمة (أدنى)', style: TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: 'max',
                            child: Text('↑ أعلى قيمة (أقصى)', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _columns[index] = col.copyWith(calculationType: val ?? 'none');
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Text(
                        col.description.isNotEmpty ? col.description : col.key,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    SizedBox(
                      width: 80,
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
                'يمكنك تحديد العملية الحسابية لكل عمود في صف الإجماليات (جمع، طرح، متوسط، عدد).',
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

          const Divider(height: 36),

          // Custom Logos Replacement Section
          Text(
            'استبدال وإدارة شعارات التقرير (Logos)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'يمكنك رفع شعار مخصص من حاسوبك لاستبدال الشعارات الافتراضية للجهة أو الجمعية',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              // Logo 1 Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF242426) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildLogoWidget(_customLogo1, _showLogo1, size: 64),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'الشعار الأيمن (الجهة / المؤسسة)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _customLogo1 != null ? 'شعار مخصص تم رفعه' : 'الشعار الافتراضي للنظام',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: _customLogo1 != null ? const Color(0xFF4F46E5) : Colors.grey,
                                    fontWeight: _customLogo1 != null ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showLogo1,
                        onChanged: (val) => setState(() => _showLogo1 = val == true),
                        title: const Text('إظهار الشعار في التقرير', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _pickCustomLogo(1),
                            icon: const Icon(Icons.file_upload_outlined, size: 16),
                            label: const Text('استبدال الشعار', style: TextStyle(fontSize: 12)),
                          ),
                          if (_customLogo1 != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'استعادة الشعار الافتراضي',
                              icon: const Icon(Icons.restart_alt_rounded, size: 20),
                              onPressed: () => _resetLogo(1),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Logo 2 Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF242426) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildLogoWidget(_customLogo2, _showLogo2, size: 64),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'الشعار الأيسر (الجمعية / الشريك)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _customLogo2 != null ? 'شعار مخصص تم رفعه' : 'الشعار الافتراضي للنظام',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: _customLogo2 != null ? const Color(0xFF4F46E5) : Colors.grey,
                                    fontWeight: _customLogo2 != null ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showLogo2,
                        onChanged: (val) => setState(() => _showLogo2 = val == true),
                        title: const Text('إظهار الشعار في التقرير', style: TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _pickCustomLogo(2),
                            icon: const Icon(Icons.file_upload_outlined, size: 16),
                            label: const Text('استبدال الشعار', style: TextStyle(fontSize: 12)),
                          ),
                          if (_customLogo2 != null) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'استعادة الشعار الافتراضي',
                              icon: const Icon(Icons.restart_alt_rounded, size: 20),
                              onPressed: () => _resetLogo(2),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const Divider(height: 36),

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

          const Divider(height: 36),

          // Custom Static Text Section
          Text(
            'نصوص ثابتة وتنبيهات عامة (Custom Static Text)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'إضافة كلام ثابت وتنويهات في التقرير (مثل تعليمات سرية البيانات أو ملاحظات الاعتماد)',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _secondaryNoteController,
            decoration: const InputDecoration(
              labelText: 'نص تنبيه أو ملاحظة ثابتة أسفل العنوان (Secondary Disclaimer)',
              hintText: 'مثال: ملاحظة: هذا التقرير سري وخاص بالمنظومة الداخلية وتعتمد بياناته لأغراض الجرد والمراجعة فقط',
              helperText: 'يظهر هذا النص كشريط تنبيهي أنيق أعلى الجدول مباشرة في ملفات PDF والإكسل',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.announcement_outlined),
            ),
          ),

          const Divider(height: 36),

          Text(
            'تذييل وهوامش الاعتماد والتوقيع (Signatures & Footer)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _preparedByController,
                  decoration: const InputDecoration(
                    labelText: 'جهة الإعداد (Prepared By)',
                    hintText: 'إعداد: إدارة الدعم الفني وتكنولوجيا المعلومات',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _approvedByController,
                  decoration: const InputDecoration(
                    labelText: 'جهة الاعتماد (Approved By)',
                    hintText: 'يعتمد، رئيس قطاع الفروع / المدير التنفيذي',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _footerNoteController,
            decoration: const InputDecoration(
              labelText: 'تذييل أسفل الصفحة (Footer Note)',
              hintText: 'يعتمد، إدارة تكنولوجيا المعلومات',
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
            title: const Text('تضمين صف الإجماليات (Totals & Calculations Row) أسفل الجدول'),
            subtitle: const Text('يقوم بحساب العمليات المحددة (جمع، متوسط، عدد، طرح) تلقائياً في نهاية التقرير'),
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

  // Live WYSIWYG Document Preview
  Widget _buildLiveDocumentPreview(ThemeData theme, bool isDark) {
    final enabledCols = _columns.where((c) => c.enabled).toList();
    final isLandscape = _orientation == 'landscape';
    final sampleRows = _selectedReportType == 'printer_consumption'
        ? _samplePrinterRows
        : _sampleTicketRows;

    var title = _titleFormatController.text.trim();
    if (title.isEmpty) {
      title = _selectedReportType == 'printer_consumption'
          ? 'استهلاك الفروع للورق عن شهر أكتوبر 2026'
          : 'تقرير تذاكر الدعم الفني والشكاوى';
    } else {
      title = title
          .replaceAll('{month}', 'أكتوبر')
          .replaceAll('{year}', '2026')
          .replaceAll('{entity}', 'الفروع')
          .replaceAll('{ticketType}', 'تذاكر الدعم الفني');
    }

    return Container(
      color: isDark ? const Color(0xFF141416) : const Color(0xFFF1F5F9),
      child: Column(
        children: [
          // Top Preview Controls Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E20) : Colors.white,
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.remove_red_eye_rounded, size: 16, color: Color(0xFF059669)),
                      SizedBox(width: 6),
                      Text(
                        'معاينة حية ومطابقة لمستند الطباعة والإكسل (Live Preview)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'اتجاه الصفحة: ${isLandscape ? "عرضي (Landscape)" : "طولي (Portrait)"}',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Text(
                  '|   الأعمدة المفعلة: ${enabledCols.length}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('تعديل الحسابات والأعمدة', style: TextStyle(fontSize: 12)),
                  onPressed: () => setState(() => _editorTabIndex = 0),
                ),
              ],
            ),
          ),

          // Document Paper View Area
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Container(
                  width: isLandscape ? 1040 : 760,
                  constraints: const BoxConstraints(minHeight: 520),
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Header with Logos and Title
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Right Logo
                          _buildLogoWidget(_customLogo1, _showLogo1, size: 70),
                          const SizedBox(width: 16),

                          // Center Organization Titles
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  _line1Controller.text.trim().isNotEmpty
                                      ? _line1Controller.text.trim()
                                      : 'جمعية رجال الأعمال والمستثمرين بالدقهلية',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _line2Controller.text.trim().isNotEmpty
                                      ? _line2Controller.text.trim()
                                      : 'مشروع تنمية المنشآت الصغيرة والحرفية',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _line3Controller.text.trim().isNotEmpty
                                      ? _line3Controller.text.trim()
                                      : 'رقم الإشهار: 777 لسنة 1995 - رقم الترخيص: 1031',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Left Logo
                          _buildLogoWidget(_customLogo2, _showLogo2, size: 70),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFCBD5E1), height: 1),
                      const SizedBox(height: 14),

                      // 2. Main Report Title
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E293B),
                        ),
                      ),

                      // 3. Secondary Static Note / Disclaimer
                      if (_secondaryNoteController.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF475569)),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _secondaryNoteController.text.trim(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // 4. Data Table Preview
                      if (enabledCols.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: const Text('لم يتم تفعيل أي أعمدة في هذا القالب بعد.'),
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildDocumentPreviewTable(enabledCols, sampleRows),
                        ),

                      const SizedBox(height: 28),

                      // 5. Signatures and Prepared By / Approved By Block
                      if (_preparedByController.text.trim().isNotEmpty ||
                          _approvedByController.text.trim().isNotEmpty) ...[
                        Row(
                          children: [
                            if (_preparedByController.text.trim().isNotEmpty)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _preparedByController.text.trim(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    const Text('التوقيع: .......................................',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                  ],
                                ),
                              ),
                            if (_approvedByController.text.trim().isNotEmpty)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _approvedByController.text.trim(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    const Text('التوقيع والاعتماد: ..............................',
                                        style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],

                      // 6. Footer Note
                      if (_footerNoteController.text.trim().isNotEmpty)
                        Text(
                          _footerNoteController.text.trim(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF64748B),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentPreviewTable(
    List<ReportColumn> enabledCols,
    List<Map<String, dynamic>> sampleRows,
  ) {
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (int i = 0; i < enabledCols.length; i++)
          i: FixedColumnWidth(math.max(70.0, (enabledCols[i].width.toDouble() * 1.1))),
      },
      border: TableBorder.all(
        color: const Color(0xFFCBD5E1),
        width: 1,
      ),
      children: [
        // Header Row
        TableRow(
          decoration: const BoxDecoration(
            color: Color(0xFFF1F5F9),
          ),
          children: [
            for (final col in enabledCols)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      col.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (col.calculationType != 'none')
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _calcBadgeLabel(col.calculationType),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),

        // Data Rows
        for (int r = 0; r < sampleRows.length; r++)
          TableRow(
            decoration: BoxDecoration(
              color: r.isEven ? Colors.white : const Color(0xFFF8FAFC),
            ),
            children: [
              for (final col in enabledCols)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  alignment: _alignmentFrom(col.align),
                  child: Text(
                    _formatPreviewValue(sampleRows[r][col.key]),
                    textAlign: _textAlignFrom(col.align),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
            ],
          ),

        // Summary Row (Calculations)
        if (_includeSummaryRow && sampleRows.isNotEmpty)
          TableRow(
            decoration: const BoxDecoration(
              color: Color(0xFFE2E8F0),
            ),
            children: [
              for (int i = 0; i < enabledCols.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  alignment: Alignment.center,
                  child: Text(
                    _computePreviewSummary(enabledCols[i], sampleRows, i),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                      color: enabledCols[i].calculationType != 'none'
                          ? const Color(0xFF312E81)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  String _calcBadgeLabel(String calc) {
    switch (calc) {
      case 'sum':
        return '∑ جمع';
      case 'avg':
        return '∅ متوسط';
      case 'count':
        return '# عدد';
      case 'diff':
        return '− طرح';
      case 'min':
        return '↓ أدنى';
      case 'max':
        return '↑ أقصى';
      default:
        return '';
    }
  }

  Alignment _alignmentFrom(String align) {
    switch (align) {
      case 'right':
        return Alignment.centerRight;
      case 'left':
        return Alignment.centerLeft;
      default:
        return Alignment.center;
    }
  }

  TextAlign _textAlignFrom(String align) {
    switch (align) {
      case 'right':
        return TextAlign.right;
      case 'left':
        return TextAlign.left;
      default:
        return TextAlign.center;
    }
  }

  String _formatPreviewValue(dynamic val) {
    if (val == null) return '—';
    if (val is num) {
      return val is int || val == val.roundToDouble()
          ? val.toInt().toString()
          : val.toStringAsFixed(1);
    }
    return val.toString();
  }

  String _computePreviewSummary(ReportColumn col, List<Map<String, dynamic>> rows, int colIdx) {
    final key = col.key;
    final calc = col.calculationType;

    if (calc == 'none') {
      if (colIdx == 0) return 'الإجمالي العام';
      if (colIdx == 1 && key != 'monoPages') return 'عدد السجلات: ${rows.length}';
      final nums = rows.map((r) => num.tryParse(r[key]?.toString() ?? '')).whereType<num>().toList();
      if (nums.isNotEmpty) {
        final s = nums.reduce((a, b) => a + b);
        final formatted = s is int || s == s.roundToDouble() ? s.toInt().toString() : s.toStringAsFixed(1);
        return formatted;
      }
      return '—';
    }

    if (calc == 'count') {
      final valid = rows.where((r) => r[key] != null && r[key].toString().isNotEmpty).length;
      return '# $valid سجلات';
    }

    final nums = rows.map((r) => num.tryParse(r[key]?.toString() ?? '')).whereType<num>().toList();
    if (nums.isEmpty) return '—';

    switch (calc) {
      case 'sum':
        final s = nums.reduce((a, b) => a + b);
        final formatted = s is int || s == s.roundToDouble() ? s.toInt().toString() : s.toStringAsFixed(1);
        return '∑ $formatted';
      case 'avg':
        final avg = nums.reduce((a, b) => a + b) / nums.length;
        return '∅ ${avg.toStringAsFixed(1)}';
      case 'diff':
        final diff = nums.length == 1
            ? nums.first
            : nums.skip(1).fold<num>(nums.first, (acc, v) => acc - v);
        return '− ${diff > 0 ? "+$diff" : diff.toString()}';
      case 'min':
        final m = nums.reduce((a, b) => a < b ? a : b);
        return '↓ $m';
      case 'max':
        final m = nums.reduce((a, b) => a > b ? a : b);
        return '↑ $m';
      default:
        return '—';
    }
  }

  // Realistic sample datasets for live previews
  static const List<Map<String, dynamic>> _samplePrinterRows = [
    {
      'index': 1,
      'branchName': 'فرع المنصورة الرئيسي',
      'printerName': 'HP LaserJet Pro 400',
      'monoPages': 4250,
      'colorPages': 1320,
      'wastePages': 45,
      'scanPages': 110,
      'totalPaper': 5615,
      'overallTotalReams': 11.2,
      'branchCode': 'BR-01',
      'ipAddress': '192.168.1.101',
      'model': 'M402dne',
      'serialNumber': 'VNB3K12345',
      'vendor': 'HP',
      'status': 'متصلة',
      'requiredReams': 12,
      'estimatedClients': 350,
      'currentTotal': 84200,
      'lifetimeTotal': 142000,
      'dataQuality': 'ممتازة 100%',
    },
    {
      'index': 2,
      'branchName': 'فرع ميت غمر',
      'printerName': 'Canon i-SENSYS LBP',
      'monoPages': 3100,
      'colorPages': 580,
      'wastePages': 30,
      'scanPages': 75,
      'totalPaper': 3710,
      'overallTotalReams': 7.4,
      'branchCode': 'BR-02',
      'ipAddress': '192.168.2.105',
      'model': 'LBP623Cdw',
      'serialNumber': 'CAN789012',
      'vendor': 'Canon',
      'status': 'متصلة',
      'requiredReams': 8,
      'estimatedClients': 230,
      'currentTotal': 52100,
      'lifetimeTotal': 91000,
      'dataQuality': 'ممتازة 100%',
    },
    {
      'index': 3,
      'branchName': 'فرع السنبلاوين',
      'printerName': 'Xerox Phaser 3020',
      'monoPages': 2850,
      'colorPages': 0,
      'wastePages': 40,
      'scanPages': 50,
      'totalPaper': 2890,
      'overallTotalReams': 5.8,
      'branchCode': 'BR-03',
      'ipAddress': '192.168.3.110',
      'model': 'Phaser 3020',
      'serialNumber': 'XRX456789',
      'vendor': 'Xerox',
      'status': 'متصلة',
      'requiredReams': 6,
      'estimatedClients': 180,
      'currentTotal': 38400,
      'lifetimeTotal': 64000,
      'dataQuality': 'جيدة 95%',
    },
    {
      'index': 4,
      'branchName': 'فرع دكرنس',
      'printerName': 'Brother HL-L2360D',
      'monoPages': 1900,
      'colorPages': 450,
      'wastePages': 20,
      'scanPages': 65,
      'totalPaper': 2370,
      'overallTotalReams': 4.7,
      'branchCode': 'BR-04',
      'ipAddress': '192.168.4.112',
      'model': 'HL-L2360D',
      'serialNumber': 'BRT112233',
      'vendor': 'Brother',
      'status': 'متصلة',
      'requiredReams': 5,
      'estimatedClients': 150,
      'currentTotal': 29100,
      'lifetimeTotal': 48000,
      'dataQuality': 'ممتازة 100%',
    },
  ];

  static const List<Map<String, dynamic>> _sampleTicketRows = [
    {
      'ticketNumber': '#TKT-1041',
      'title': 'عطل بطابعة الاستقبال',
      'status': 'مغلقة',
      'priority': 'عالية',
      'department': 'الدعم الفني',
      'branch': 'فرع المنصورة',
      'technician': 'أحمد محمود',
      'resolutionHours': 3.5,
      'updatesCount': 4,
      'rating': '★★★★★',
      'lastMessage': 'تم استبدال بكرة سحب الورق بنجاح',
    },
    {
      'ticketNumber': '#TKT-1042',
      'title': 'طلب حبر أسود جديد',
      'status': 'تم الحل',
      'priority': 'عادية',
      'department': 'المشتريات',
      'branch': 'فرع ميت غمر',
      'technician': 'محمد سعيد',
      'resolutionHours': 5.0,
      'updatesCount': 2,
      'rating': '★★★★☆',
      'lastMessage': 'تم تسليم عبوة الحبر لمسؤول الفرع',
    },
    {
      'ticketNumber': '#TKT-1043',
      'title': 'انحشار ورق متكرر في الدرج 2',
      'status': 'قيد المتابعة',
      'priority': 'حرجة',
      'department': 'الصيانة',
      'branch': 'فرع طلخا',
      'technician': 'محمود حسن',
      'resolutionHours': 12.0,
      'updatesCount': 5,
      'rating': '—',
      'lastMessage': 'جارٍ فحص التروس الداخلية للطابعة',
    },
    {
      'ticketNumber': '#TKT-1044',
      'title': 'تهيئة طابعة شبكية جديدة',
      'status': 'مغلقة',
      'priority': 'منخفضة',
      'department': 'الشبكات',
      'branch': 'فرع السنبلاوين',
      'technician': 'خالد إبراهيم',
      'resolutionHours': 1.5,
      'updatesCount': 3,
      'rating': '★★★★★',
      'lastMessage': 'تم تثبيت التعريفات لجميع أجهزة الفرع',
    },
  ];
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
