import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/providers/providers.dart';
import '../models/it_asset_models.dart';
import 'it_assets_advanced_tabs.dart';

class ItAssetsScreen extends ConsumerStatefulWidget {
  const ItAssetsScreen({super.key, this.isWrapped = false});

  final bool isWrapped;

  @override
  ConsumerState<ItAssetsScreen> createState() => _ItAssetsScreenState();
}

class _ItAssetsScreenState extends ConsumerState<ItAssetsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  ItAssetsOverview? _overview;
  List<ItAsset> _assets = const [];
  List<ItSparePart> _spareParts = const [];
  List<ItOperation> _operations = const [];
  List<ItAuditEntry> _auditLog = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 10, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authControllerProvider).valueOrNull;
    if (user == null || !user.canViewItAssets) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repository = ref.read(itAssetsRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repository.fetchOverview(),
        repository.fetchAssets(),
        repository.fetchSpareParts(),
        repository.fetchOperations(),
        if (user.canAuditItAssets)
          repository.fetchAuditLog()
        else
          Future<List<ItAuditEntry>>.value(const []),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as ItAssetsOverview;
        _assets = results[1] as List<ItAsset>;
        _spareParts = results[2] as List<ItSparePart>;
        _operations = results[3] as List<ItOperation>;
        _auditLog = results[4] as List<ItAuditEntry>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (user == null || !user.canViewItAssets) {
      return const Center(
        child: Text('ليس لديك صلاحية لعرض نظام إدارة أصول IT.'),
      );
    }
    final content = Column(
      children: [
        _Header(onRefresh: _load),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'لوحة المتابعة'),
            Tab(icon: Icon(Icons.computer_outlined), text: 'الأجهزة والعهد'),
            Tab(icon: Icon(Icons.memory_outlined), text: 'قطع الغيار'),
            Tab(icon: Icon(Icons.swap_horiz_rounded), text: 'الحركات والنقل'),
            Tab(icon: Icon(Icons.build_outlined), text: 'الصيانة'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'الجرد والتالف'),
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'مركز المراجعة'),
            Tab(
              icon: Icon(Icons.qr_code_scanner_rounded),
              text: 'الجرد الفعلي',
            ),
            Tab(icon: Icon(Icons.gavel_outlined), text: 'الرقابة والإعدادات'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'التقارير والجودة'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _DashboardTab(overview: _overview!),
                    _AssetsTab(
                      assets: _assets,
                      canManage: user.canManageItAssets,
                      canDelete: user.canDeleteItAssets,
                      onAdd: () => _showAssetDialog(),
                      onEdit: _showAssetDialog,
                      onDelete: _deleteAsset,
                      onLabel: _downloadAssetLabel,
                      onAttachments: (asset) =>
                          _showAttachments('asset', asset.id),
                    ),
                    _SparePartsTab(
                      parts: _spareParts,
                      canManage: user.canManageItAssets,
                      canDelete: user.canDeleteItAssets,
                      onAdd: () => _showPartDialog(),
                      onEdit: _showPartDialog,
                      onDelete: _deleteSparePart,
                      onLabel: _downloadSparePartLabel,
                    ),
                    _OperationsTab(
                      operations: _operations
                          .where(
                            (entry) => entry.operationType != 'maintenance',
                          )
                          .toList(),
                      assets: _assets,
                      parts: _spareParts,
                      canExecute: user.canExecuteItAssets,
                      onCreate: _showOperationDialog,
                      onComplete: _showCompleteDialog,
                      onPdf: _downloadOperationPdf,
                      onSign: _signOperation,
                      onAttachments: (operation) =>
                          _showAttachments('operation', operation.id),
                    ),
                    _OperationsTab(
                      operations: _operations
                          .where(
                            (entry) => entry.operationType == 'maintenance',
                          )
                          .toList(),
                      assets: _assets,
                      parts: _spareParts,
                      canExecute: user.canExecuteItAssets,
                      maintenanceOnly: true,
                      onCreate: _showOperationDialog,
                      onComplete: _showCompleteDialog,
                      onPdf: _downloadOperationPdf,
                      onSign: _signOperation,
                      onAttachments: (operation) =>
                          _showAttachments('operation', operation.id),
                    ),
                    _InventoryTab(
                      operations: _operations
                          .where(
                            (entry) =>
                                entry.operationType == 'inventory' ||
                                entry.operationType == 'damaged',
                          )
                          .toList(),
                      damagedAssets: _assets
                          .where(
                            (entry) => const [
                              'damaged',
                              'damaged_store',
                              'scrapped',
                              'lost',
                            ].contains(entry.status),
                          )
                          .toList(),
                    ),
                    _AuditTab(
                      operations: _operations,
                      logs: _auditLog,
                      canAudit: user.canAuditItAssets,
                      onReview: _showAuditDialog,
                    ),
                    const ItInventoryManagementTab(),
                    const ItGovernanceTab(),
                    const ItReportsAndQualityTab(),
                  ],
                ),
        ),
      ],
    );
    return widget.isWrapped
        ? content
        : Scaffold(body: SafeArea(child: content));
  }

  Future<String?> _confirmDelete(String title) async {
    final reason = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: reason,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'سبب الحذف / الأرشفة',
            helperText: 'سيظل الحدث محفوظًا في سجل العمليات.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (reason.text.trim().isNotEmpty) {
                Navigator.pop(context, reason.text.trim());
              }
            },
            child: const Text('تأكيد الأرشفة'),
          ),
        ],
      ),
    );
    reason.dispose();
    return result;
  }

  Future<void> _deleteAsset(ItAsset asset) async {
    final reason = await _confirmDelete('أرشفة الجهاز ${asset.assetCode}؟');
    if (reason == null) return;
    await ref
        .read(itAssetsRepositoryProvider)
        .deleteAsset(asset.id, reason: reason);
    await _load();
  }

  Future<void> _deleteSparePart(ItSparePart part) async {
    final reason = await _confirmDelete('أرشفة قطعة الغيار ${part.partCode}؟');
    if (reason == null) return;
    await ref
        .read(itAssetsRepositoryProvider)
        .deleteSparePart(part.id, reason: reason);
    await _load();
  }

  Future<void> _showAssetDialog([ItAsset? asset]) async {
    final code = TextEditingController(text: asset?.assetCode ?? '');
    final type = TextEditingController(text: asset?.assetType ?? '');
    final category = TextEditingController(text: asset?.category ?? '');
    final brand = TextEditingController(text: asset?.brand ?? '');
    final model = TextEditingController(text: asset?.model ?? '');
    final serial = TextEditingController(text: asset?.serialNumber ?? '');
    final location = TextEditingController(text: asset?.location ?? '');
    final assigned = TextEditingController(text: asset?.assignedTo ?? '');
    final branch = TextEditingController(text: asset?.branchName ?? '');
    final vendor = TextEditingController(text: asset?.vendor ?? '');
    final invoice = TextEditingController(text: asset?.invoiceNumber ?? '');
    final purchaseDate = TextEditingController(
      text: asset?.purchaseDate?.toIso8601String().split('T').first ?? '',
    );
    final warrantyEnd = TextEditingController(
      text: asset?.warrantyEndDate?.toIso8601String().split('T').first ?? '',
    );
    final notes = TextEditingController(text: asset?.notes ?? '');
    var status = asset?.status ?? 'available';
    var condition = asset?.condition ?? 'good';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(
            asset == null ? 'إضافة جهاز جديد' : 'تعديل بيانات الجهاز',
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _field(code, 'كود الجهاز', enabled: asset == null),
                  _field(type, 'نوع الجهاز'),
                  _field(category, 'التصنيف'),
                  _field(brand, 'الماركة'),
                  _field(model, 'الموديل'),
                  _field(serial, 'Serial Number'),
                  _field(location, 'المكان الحالي'),
                  _field(branch, 'الفرع'),
                  _field(assigned, 'الموظف المستلم'),
                  _field(vendor, 'المورد'),
                  _field(invoice, 'رقم الفاتورة'),
                  _field(purchaseDate, 'تاريخ الشراء YYYY-MM-DD'),
                  _field(warrantyEnd, 'نهاية الضمان YYYY-MM-DD'),
                  _dropdown(
                    'الحالة',
                    status,
                    _assetStatuses,
                    (value) => setLocalState(() => status = value),
                  ),
                  _dropdown(
                    'حالة الجهاز',
                    condition,
                    const {
                      'good': 'جيد',
                      'fair': 'متوسط',
                      'damaged': 'تالف',
                      'not_repairable': 'غير قابل للإصلاح',
                    },
                    (value) => setLocalState(() => condition = value),
                  ),
                  SizedBox(
                    width: 696,
                    child: TextField(
                      controller: notes,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'ملاحظات'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (code.text.trim().isEmpty || type.text.trim().isEmpty) {
                  _toast('كود الجهاز ونوعه مطلوبان.');
                  return;
                }
                await ref.read(itAssetsRepositoryProvider).saveAsset({
                  'assetCode': code.text.trim(),
                  'assetType': type.text.trim(),
                  'category': category.text.trim(),
                  'brand': brand.text.trim(),
                  'model': model.text.trim(),
                  'serialNumber': serial.text.trim(),
                  'location': location.text.trim(),
                  'branchName': branch.text.trim(),
                  'assignedTo': assigned.text.trim(),
                  'vendor': vendor.text.trim(),
                  'invoiceNumber': invoice.text.trim(),
                  'purchaseDate': purchaseDate.text.trim(),
                  'warrantyEndDate': warrantyEnd.text.trim(),
                  'status': status,
                  'condition': condition,
                  'notes': notes.text.trim(),
                  'changeReason': asset == null
                      ? 'تسجيل جهاز جديد'
                      : 'تعديل من شاشة إدارة الأصول',
                }, assetId: asset?.id);
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      code,
      type,
      category,
      brand,
      model,
      serial,
      location,
      assigned,
      branch,
      notes,
      vendor,
      invoice,
      purchaseDate,
      warrantyEnd,
    ]) {
      controller.dispose();
    }
    if (saved == true) await _load();
  }

  Future<void> _showPartDialog([ItSparePart? part]) async {
    final code = TextEditingController(text: part?.partCode ?? '');
    final name = TextEditingController(text: part?.name ?? '');
    final category = TextEditingController(text: part?.category ?? '');
    final brand = TextEditingController(text: part?.brand ?? '');
    final model = TextEditingController(text: part?.model ?? '');
    final available = TextEditingController(
      text: part?.quantityAvailable.toString() ?? '0',
    );
    final reserved = TextEditingController(
      text: part?.quantityReserved.toString() ?? '0',
    );
    final damaged = TextEditingController(
      text: part?.damagedQuantity.toString() ?? '0',
    );
    final minimum = TextEditingController(
      text: part?.minimumQuantity.toString() ?? '0',
    );
    final critical = TextEditingController(
      text: part?.criticalQuantity.toString() ?? '0',
    );
    final preferred = TextEditingController(
      text: part?.preferredQuantity.toString() ?? '0',
    );
    final location = TextEditingController(text: part?.location ?? '');
    var serialized = part?.hasSerialNumbers ?? false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(part == null ? 'إضافة قطعة غيار' : 'تعديل قطعة الغيار'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _field(code, 'كود القطعة', enabled: part == null),
                  _field(name, 'اسم القطعة'),
                  _field(category, 'التصنيف'),
                  _field(brand, 'الماركة'),
                  _field(model, 'الموديل'),
                  _numberField(available, 'الكمية السليمة'),
                  _numberField(reserved, 'الكمية المحجوزة'),
                  _numberField(damaged, 'الكمية التالفة'),
                  _numberField(minimum, 'حد إعادة الطلب'),
                  _numberField(critical, 'الحد الحرج'),
                  _numberField(preferred, 'الكمية المفضلة'),
                  _field(location, 'المكان'),
                  SizedBox(
                    width: 340,
                    child: SwitchListTile(
                      title: const Text('تتبع Serial Number'),
                      value: serialized,
                      onChanged: (value) =>
                          setLocalState(() => serialized = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                await ref.read(itAssetsRepositoryProvider).saveSparePart({
                  'partCode': code.text.trim(),
                  'name': name.text.trim(),
                  'category': category.text.trim(),
                  'brand': brand.text.trim(),
                  'model': model.text.trim(),
                  'quantityAvailable': int.tryParse(available.text) ?? 0,
                  'quantityReserved': int.tryParse(reserved.text) ?? 0,
                  'damagedQuantity': int.tryParse(damaged.text) ?? 0,
                  'minimumQuantity': int.tryParse(minimum.text) ?? 0,
                  'criticalQuantity': int.tryParse(critical.text) ?? 0,
                  'preferredQuantity': int.tryParse(preferred.text) ?? 0,
                  'location': location.text.trim(),
                  'hasSerialNumbers': serialized,
                }, sparePartId: part?.id);
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      code,
      name,
      category,
      brand,
      model,
      available,
      reserved,
      damaged,
      minimum,
      critical,
      preferred,
      location,
    ]) {
      controller.dispose();
    }
    if (saved == true) await _load();
  }

  Future<void> _showOperationDialog({bool maintenanceOnly = false}) async {
    var type = maintenanceOnly ? 'maintenance' : 'movement';
    String? assetId;
    String? partId;
    final title = TextEditingController(
      text: maintenanceOnly ? 'طلب صيانة' : '',
    );
    final quantity = TextEditingController(text: '0');
    final from = TextEditingController();
    final to = TextEditingController();
    final assigned = TextEditingController();
    final details = TextEditingController();
    final rootCause = TextEditingController();
    final expectedReturn = TextEditingController();
    final oldPartCode = TextEditingController();
    var priority = 'medium';
    var requiresAudit = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(maintenanceOnly ? 'فتح طلب صيانة' : 'إنشاء حركة جديدة'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (!maintenanceOnly)
                    _dropdown(
                      'نوع الحركة',
                      type,
                      _operationTypes,
                      (value) => setLocalState(() => type = value),
                    ),
                  _field(title, 'عنوان العملية'),
                  SizedBox(
                    width: 340,
                    child: DropdownButtonFormField<String?>(
                      initialValue: assetId,
                      decoration: const InputDecoration(labelText: 'الجهاز'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('بدون جهاز'),
                        ),
                        ..._assets.map(
                          (asset) => DropdownMenuItem(
                            value: asset.id,
                            child: Text(
                              '${asset.assetCode} - ${asset.assetType}',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => assetId = value,
                    ),
                  ),
                  SizedBox(
                    width: 340,
                    child: DropdownButtonFormField<String?>(
                      initialValue: partId,
                      decoration: const InputDecoration(
                        labelText: 'قطعة الغيار',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('بدون قطعة'),
                        ),
                        ..._spareParts.map(
                          (part) => DropdownMenuItem(
                            value: part.id,
                            child: Text('${part.partCode} - ${part.name}'),
                          ),
                        ),
                      ],
                      onChanged: (value) => partId = value,
                    ),
                  ),
                  _numberField(quantity, 'الكمية'),
                  _field(from, 'من مكان'),
                  _field(to, 'إلى مكان'),
                  _field(assigned, 'الموظف / المستلم'),
                  if (maintenanceOnly)
                    _dropdown(
                      'الأولوية',
                      priority,
                      const {
                        'low': 'منخفضة - 5 أيام',
                        'medium': 'متوسطة - 3 أيام',
                        'high': 'عالية - يوم',
                        'critical': 'حرجة - 4 ساعات',
                      },
                      (value) => setLocalState(() => priority = value),
                    ),
                  _field(rootCause, 'السبب الجذري للعطل'),
                  if (type == 'temporary_assignment')
                    _field(expectedReturn, 'تاريخ الإرجاع المتوقع YYYY-MM-DD'),
                  if (type == 'replacement')
                    _field(oldPartCode, 'كود / سيريال القطعة القديمة'),
                  SizedBox(
                    width: 696,
                    child: TextField(
                      controller: details,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'التفاصيل والسبب',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 340,
                    child: SwitchListTile(
                      title: const Text('تحتاج اعتماد المراجعة'),
                      value: requiresAudit,
                      onChanged: (value) =>
                          setLocalState(() => requiresAudit = value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                await ref.read(itAssetsRepositoryProvider).createOperation({
                  'operationType': type,
                  'title': title.text.trim(),
                  'assetId': assetId,
                  'sparePartId': partId,
                  'quantity': int.tryParse(quantity.text) ?? 0,
                  'fromLocation': from.text.trim(),
                  'toLocation': to.text.trim(),
                  'assignedTo': assigned.text.trim(),
                  'details': details.text.trim(),
                  'rootCause': rootCause.text.trim(),
                  'priority': priority,
                  'expectedReturnDate': expectedReturn.text.trim(),
                  'metadata': {
                    if (oldPartCode.text.trim().isNotEmpty)
                      'oldPartCode': oldPartCode.text.trim(),
                  },
                  'requiresAudit': requiresAudit,
                });
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              },
              child: const Text('إنشاء المستند'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      title,
      quantity,
      from,
      to,
      assigned,
      details,
      rootCause,
      expectedReturn,
      oldPartCode,
    ]) {
      controller.dispose();
    }
    if (saved == true) await _load();
  }

  Future<void> _showAuditDialog(ItOperation operation) async {
    final note = TextEditingController();
    final reference = TextEditingController();
    bool? approved;
    approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('مراجعة ${operation.documentNumber}'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(operation.title),
              const SizedBox(height: 16),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'رقم القيد / مرجع المراجعة',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات المراجعة',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رفض'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
    if (approved == null) return;
    await ref
        .read(itAssetsRepositoryProvider)
        .acknowledgeOperation(
          operation.id,
          approved: approved,
          auditNote: note.text.trim(),
          auditReference: reference.text.trim(),
        );
    note.dispose();
    reference.dispose();
    await _load();
  }

  Future<void> _showCompleteDialog(ItOperation operation) async {
    final solution = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تنفيذ ${operation.documentNumber}'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: solution,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: operation.operationType == 'maintenance'
                  ? 'الحل والإجراء النهائي'
                  : 'ملاحظات التنفيذ',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تنفيذ وإغلاق'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(itAssetsRepositoryProvider)
          .completeOperation(operation.id, solution: solution.text.trim());
      await _load();
    }
    solution.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _downloadAssetLabel(ItAsset asset) async {
    final repository = ref.read(itAssetsRepositoryProvider);
    await ref.read(desktopFileSaveServiceProvider).executeSaveJob({
      'fileName': '${asset.assetCode}-label.pdf',
      'mimeType': 'application/pdf',
      'downloadUrl': repository.assetLabelUrl(asset.id),
    });
  }

  Future<void> _downloadSparePartLabel(ItSparePart part) async {
    final repository = ref.read(itAssetsRepositoryProvider);
    await ref.read(desktopFileSaveServiceProvider).executeSaveJob({
      'fileName': '${part.partCode}-label.pdf',
      'mimeType': 'application/pdf',
      'downloadUrl': repository.sparePartLabelUrl(part.id),
    });
  }

  Future<void> _downloadOperationPdf(ItOperation operation) async {
    final repository = ref.read(itAssetsRepositoryProvider);
    await ref.read(desktopFileSaveServiceProvider).executeSaveJob({
      'fileName': '${operation.documentNumber}.pdf',
      'mimeType': 'application/pdf',
      'downloadUrl': repository.operationPdfUrl(operation.id),
    });
  }

  Future<void> _signOperation(ItOperation operation) async {
    final password = TextEditingController();
    final role = TextEditingController(text: 'المعتمد');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('توقيع ${operation.documentNumber}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: role,
                decoration: const InputDecoration(labelText: 'صفة التوقيع'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور للتأكيد',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('توقيع'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(itAssetsRepositoryProvider)
          .signOperation(
            operation.id,
            password: password.text,
            role: role.text,
          );
      await _load();
    }
    password.dispose();
    role.dispose();
  }

  Future<void> _showAttachments(String entityType, String entityId) async {
    var attachments = await ref
        .read(itAssetsRepositoryProvider)
        .fetchAttachments(entityType, entityId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('المرفقات'),
          content: SizedBox(
            width: 620,
            height: 420,
            child: attachments.isEmpty
                ? const Center(child: Text('لا توجد مرفقات.'))
                : ListView(
                    children: attachments
                        .map(
                          (attachment) => ListTile(
                            leading: const Icon(Icons.attach_file_rounded),
                            title: Text(attachment.originalName),
                            subtitle: Text(
                              '${attachment.uploadedByName} • ${attachment.size} bytes',
                            ),
                            trailing: IconButton(
                              tooltip: 'تنزيل',
                              onPressed: () async {
                                final repository = ref.read(
                                  itAssetsRepositoryProvider,
                                );
                                await ref
                                    .read(desktopFileSaveServiceProvider)
                                    .executeSaveJob({
                                      'fileName': attachment.originalName,
                                      'mimeType': attachment.mimeType,
                                      'downloadUrl': repository.attachmentUrl(
                                        attachment.id,
                                      ),
                                    });
                              },
                              icon: const Icon(Icons.download_rounded),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            FilledButton.tonalIcon(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  withData: true,
                );
                final file = result?.files.single;
                if (file == null) return;
                await ref
                    .read(itAssetsRepositoryProvider)
                    .uploadAttachment(
                      entityType: entityType,
                      entityId: entityId,
                      fileName: file.name,
                      filePath: file.path,
                      bytes: file.bytes,
                    );
                attachments = await ref
                    .read(itAssetsRepositoryProvider)
                    .fetchAttachments(entityType, entityId);
                setLocalState(() {});
              },
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('رفع مرفق'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.inventory_rounded),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IT Asset & Maintenance Management',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              Text('إدارة الأجهزة والعهد والمخازن والصيانة والجرد والمراجعة'),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'تحديث',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
  );
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({required this.overview});
  final ItAssetsOverview overview;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        'إجمالي الأجهزة',
        overview.totalAssets,
        Icons.devices_rounded,
        Colors.blue,
      ),
      (
        'المتاح',
        overview.availableAssets,
        Icons.check_circle_outline,
        Colors.green,
      ),
      (
        'في العهدة',
        overview.assignedAssets,
        Icons.badge_outlined,
        Colors.indigo,
      ),
      (
        'تحت الصيانة',
        overview.maintenanceAssets,
        Icons.build_outlined,
        Colors.orange,
      ),
      (
        'التالف / المفقود',
        overview.damagedAssets,
        Icons.warning_amber_rounded,
        Colors.red,
      ),
      (
        'أنواع قطع الغيار',
        overview.totalSpareParts,
        Icons.memory_rounded,
        Colors.teal,
      ),
      (
        'مخزون منخفض',
        overview.lowStock,
        Icons.trending_down_rounded,
        Colors.deepOrange,
      ),
      (
        'عمليات معلقة',
        overview.pendingOperations,
        Icons.pending_actions_rounded,
        Colors.purple,
      ),
      (
        'صيانة مفتوحة',
        overview.openMaintenance,
        Icons.handyman_outlined,
        Colors.brown,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: cards
              .map(
                (card) => _StatCard(
                  label: card.$1,
                  value: card.$2,
                  icon: card.$3,
                  color: card.$4,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text(
          'آخر الحركات',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _OperationTable(operations: overview.recentOperations),
      ],
    );
  }
}

class _AssetsTab extends StatelessWidget {
  const _AssetsTab({
    required this.assets,
    required this.canManage,
    required this.canDelete,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onLabel,
    required this.onAttachments,
  });
  final List<ItAsset> assets;
  final bool canManage;
  final bool canDelete;
  final VoidCallback onAdd;
  final ValueChanged<ItAsset> onEdit;
  final ValueChanged<ItAsset> onDelete;
  final ValueChanged<ItAsset> onLabel;
  final ValueChanged<ItAsset> onAttachments;

  @override
  Widget build(BuildContext context) => _SectionList<ItAsset>(
    title: 'سجل الأجهزة والعهد',
    count: assets.length,
    addLabel: 'إضافة جهاز',
    canAdd: canManage,
    onAdd: onAdd,
    items: assets,
    itemBuilder: (asset) => Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            asset.assetCode.substring(0, asset.assetCode.length.clamp(0, 2)),
          ),
        ),
        title: Text('${asset.assetCode} • ${asset.assetType}'),
        subtitle: Text(
          '${asset.brand} ${asset.model}  |  ${asset.location}'
          '${asset.assignedTo.isEmpty ? '' : '  |  عهدة: ${asset.assignedTo}'}',
        ),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusChip(status: asset.status),
            IconButton(
              tooltip: 'Timeline',
              onPressed: () => _showTimeline(context, asset),
              icon: const Icon(Icons.timeline_rounded),
            ),
            IconButton(
              tooltip: 'طباعة QR Label',
              onPressed: () => onLabel(asset),
              icon: const Icon(Icons.qr_code_2_rounded),
            ),
            IconButton(
              tooltip: 'المرفقات',
              onPressed: () => onAttachments(asset),
              icon: const Icon(Icons.attach_file_rounded),
            ),
            if (canManage)
              IconButton(
                tooltip: 'تعديل',
                onPressed: () => onEdit(asset),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (canDelete)
              IconButton(
                tooltip: 'أرشفة الجهاز',
                onPressed: () => onDelete(asset),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SparePartsTab extends StatelessWidget {
  const _SparePartsTab({
    required this.parts,
    required this.canManage,
    required this.canDelete,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onLabel,
  });
  final List<ItSparePart> parts;
  final bool canManage;
  final bool canDelete;
  final VoidCallback onAdd;
  final ValueChanged<ItSparePart> onEdit;
  final ValueChanged<ItSparePart> onDelete;
  final ValueChanged<ItSparePart> onLabel;

  @override
  Widget build(BuildContext context) => _SectionList<ItSparePart>(
    title: 'مخزون قطع الغيار',
    count: parts.length,
    addLabel: 'إضافة قطعة',
    canAdd: canManage,
    onAdd: onAdd,
    items: parts,
    itemBuilder: (part) => Card(
      child: ListTile(
        leading: Icon(
          part.isLowStock ? Icons.warning_amber_rounded : Icons.memory_rounded,
          color: part.isLowStock ? Colors.deepOrange : Colors.teal,
        ),
        title: Text('${part.partCode} • ${part.name}'),
        subtitle: Text(
          'متاح: ${part.usableQuantity}  |  محجوز: ${part.quantityReserved}  |  تالف: ${part.damagedQuantity}  |  ${part.location}',
        ),
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: 'طباعة QR Label',
              onPressed: () => onLabel(part),
              icon: const Icon(Icons.qr_code_2_rounded),
            ),
            if (canManage)
              IconButton(
                onPressed: () => onEdit(part),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (canDelete)
              IconButton(
                tooltip: 'أرشفة قطعة الغيار',
                onPressed: () => onDelete(part),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
          ],
        ),
      ),
    ),
  );
}

class _OperationsTab extends StatelessWidget {
  const _OperationsTab({
    required this.operations,
    required this.assets,
    required this.parts,
    required this.canExecute,
    required this.onCreate,
    required this.onComplete,
    required this.onPdf,
    required this.onSign,
    required this.onAttachments,
    this.maintenanceOnly = false,
  });
  final List<ItOperation> operations;
  final List<ItAsset> assets;
  final List<ItSparePart> parts;
  final bool canExecute;
  final bool maintenanceOnly;
  final Future<void> Function({bool maintenanceOnly}) onCreate;
  final ValueChanged<ItOperation> onComplete;
  final ValueChanged<ItOperation> onPdf;
  final ValueChanged<ItOperation> onSign;
  final ValueChanged<ItOperation> onAttachments;

  @override
  Widget build(BuildContext context) => _SectionList<ItOperation>(
    title: maintenanceOnly ? 'طلبات الصيانة' : 'الحركات وأوامر النقل والعهد',
    count: operations.length,
    addLabel: maintenanceOnly ? 'فتح طلب صيانة' : 'إنشاء حركة',
    canAdd: canExecute,
    onAdd: () => onCreate(maintenanceOnly: maintenanceOnly),
    items: operations,
    itemBuilder: (operation) => Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        operation.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${operation.documentNumber} • ${_operationTypeLabel(operation.operationType)}',
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: operation.status),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                if (operation.asset != null)
                  _OperationInfo(
                    icon: Icons.computer_outlined,
                    value: operation.asset!.assetCode,
                  ),
                if (operation.createdByName.isNotEmpty)
                  _OperationInfo(
                    icon: Icons.person_outline,
                    value: operation.createdByName,
                  ),
                _OperationInfo(
                  icon: operation.signedByName.isEmpty
                      ? Icons.warning_amber_rounded
                      : Icons.verified_user_outlined,
                  value: operation.signedByName.isEmpty
                      ? 'غير موقعة — لا يمكن التنفيذ'
                      : operation.signedByName,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              children: [
                IconButton(
                  tooltip: 'تنزيل PDF',
                  onPressed: () => onPdf(operation),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                IconButton(
                  tooltip: 'المرفقات',
                  onPressed: () => onAttachments(operation),
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                OutlinedButton.icon(
                  onPressed: operation.signedByName.isEmpty
                      ? () => onSign(operation)
                      : null,
                  icon: const Icon(Icons.draw_outlined),
                  label: Text(
                    operation.signedByName.isEmpty
                        ? 'توقيع الحركة'
                        : 'تم التوقيع',
                  ),
                ),
                if (canExecute &&
                    const [
                      'approved',
                      'in_progress',
                    ].contains(operation.status))
                  FilledButton.icon(
                    onPressed: operation.signedByName.isEmpty
                        ? null
                        : () => onComplete(operation),
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('تنفيذ الحركة'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _OperationInfo extends StatelessWidget {
  const _OperationInfo({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [Icon(icon, size: 17), const SizedBox(width: 5), Text(value)],
  );
}

class _InventoryTab extends StatelessWidget {
  const _InventoryTab({required this.operations, required this.damagedAssets});
  final List<ItOperation> operations;
  final List<ItAsset> damagedAssets;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'الأجهزة التالفة والمفقودة (${damagedAssets.length})',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      ...damagedAssets.map(
        (asset) => Card(
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            title: Text('${asset.assetCode} • ${asset.assetType}'),
            subtitle: Text('${asset.location} • ${asset.assignedTo}'),
            trailing: _StatusChip(status: asset.status),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        'مستندات الجرد والتالف (${operations.length})',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 10),
      _OperationTable(operations: operations),
    ],
  );
}

class _AuditTab extends StatelessWidget {
  const _AuditTab({
    required this.operations,
    required this.logs,
    required this.canAudit,
    required this.onReview,
  });
  final List<ItOperation> operations;
  final List<ItAuditEntry> logs;
  final bool canAudit;
  final ValueChanged<ItOperation> onReview;

  @override
  Widget build(BuildContext context) {
    if (!canAudit) {
      return const Center(child: Text('ليس لديك صلاحية مركز المراجعة.'));
    }
    final pending = operations
        .where((entry) => entry.status == 'pending_audit')
        .toList();
    final signed = operations
        .where((entry) => entry.signedByName.isNotEmpty)
        .length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _AuditMetric(
              label: 'بانتظار المراجعة',
              value: '${pending.length}',
              icon: Icons.pending_actions_outlined,
            ),
            _AuditMetric(
              label: 'حركات موقعة',
              value: '$signed',
              icon: Icons.verified_user_outlined,
            ),
            _AuditMetric(
              label: 'أحداث مسجلة',
              value: '${logs.length}',
              icon: Icons.history_rounded,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'بانتظار المراجعة (${pending.length})',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ...pending.map(
          (operation) => Card(
            child: ListTile(
              title: Text('${operation.documentNumber} • ${operation.title}'),
              subtitle: Text(operation.details),
              trailing: FilledButton.tonal(
                onPressed: () => onReview(operation),
                child: const Text('مراجعة'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'سجل العمليات غير القابل للحذف (${logs.length})',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ...logs.map(
          (log) => Card.outlined(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  log.action.contains('delete')
                      ? Icons.delete_outline
                      : log.action.contains('signature')
                      ? Icons.draw_outlined
                      : log.action.contains('export')
                      ? Icons.download_outlined
                      : Icons.history_rounded,
                ),
              ),
              title: Text(
                log.summary,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${log.actorName} • ${_formatDate(log.createdAt)}'
                '${log.documentNumber == null ? '' : ' • ${log.documentNumber}'}',
              ),
              trailing: Chip(label: Text(log.entityType)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditMetric extends StatelessWidget {
  const _AuditMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 30),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(label),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionList<T> extends StatelessWidget {
  const _SectionList({
    required this.title,
    required this.count,
    required this.addLabel,
    required this.canAdd,
    required this.onAdd,
    required this.items,
    required this.itemBuilder,
  });
  final String title;
  final int count;
  final String addLabel;
  final bool canAdd;
  final VoidCallback onAdd;
  final List<T> items;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              '$title ($count)',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            if (canAdd)
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text(addLabel),
              ),
          ],
        ),
      ),
      Expanded(
        child: items.isEmpty
            ? const Center(child: Text('لا توجد بيانات حتى الآن.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: items.length,
                itemBuilder: (_, index) => itemBuilder(items[index]),
              ),
      ),
    ],
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 210,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            Text(label),
          ],
        ),
      ],
    ),
  );
}

class _OperationTable extends StatelessWidget {
  const _OperationTable({required this.operations});
  final List<ItOperation> operations;

  @override
  Widget build(BuildContext context) {
    if (operations.isEmpty) return const Text('لا توجد حركات مسجلة.');
    return Card(
      child: Column(
        children: operations
            .map(
              (operation) => ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text('${operation.documentNumber} • ${operation.title}'),
                subtitle: Text(
                  '${_operationTypeLabel(operation.operationType)} • ${_formatDate(operation.createdAt)}',
                ),
                trailing: _StatusChip(status: operation.status),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'available' || 'in_stock' || 'completed' || 'approved' => Colors.green,
      'assigned' || 'assigned_to_employee' || 'in_branch' => Colors.blue,
      'in_maintenance' ||
      'external_maintenance' ||
      'in_progress' => Colors.orange,
      'damaged' || 'damaged_store' || 'rejected' || 'lost' => Colors.red,
      'pending_audit' || 'pending_inspection' => Colors.purple,
      'scrapped' || 'cancelled' => Colors.grey,
      _ => Colors.blueGrey,
    };
    return Chip(
      label: Text(_statusLabel(status)),
      side: BorderSide(color: color.withValues(alpha: .35)),
      backgroundColor: color.withValues(alpha: .1),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, size: 48),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    ),
  );
}

Widget _field(
  TextEditingController controller,
  String label, {
  bool enabled = true,
}) => SizedBox(
  width: 340,
  child: TextField(
    controller: controller,
    enabled: enabled,
    decoration: InputDecoration(labelText: label),
  ),
);

Widget _numberField(TextEditingController controller, String label) => SizedBox(
  width: 340,
  child: TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
  ),
);

Widget _dropdown(
  String label,
  String value,
  Map<String, String> values,
  ValueChanged<String> onChanged,
) => SizedBox(
  width: 340,
  child: DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: values.entries
        .map(
          (entry) =>
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        )
        .toList(),
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  ),
);

void _showTimeline(BuildContext context, ItAsset asset) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Timeline - ${asset.assetCode}'),
      content: SizedBox(
        width: 600,
        height: 480,
        child: asset.timeline.isEmpty
            ? const Center(child: Text('لا توجد حركات مسجلة.'))
            : ListView(
                children: asset.timeline.reversed
                    .map(
                      (entry) => ListTile(
                        leading: const Icon(Icons.radio_button_checked_rounded),
                        title: Text(
                          entry.details.isEmpty ? entry.action : entry.details,
                        ),
                        subtitle: Text(
                          '${entry.performedByName} • ${_formatDate(entry.createdAt)}'
                          '${entry.documentNumber == null ? '' : ' • ${entry.documentNumber}'}',
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}

const _assetStatuses = <String, String>{
  'available': 'متاح',
  'in_stock': 'في المخزن',
  'assigned_to_employee': 'عهدة موظف',
  'in_branch': 'في فرع',
  'in_maintenance': 'تحت الصيانة',
  'external_maintenance': 'صيانة خارجية',
  'damaged': 'تالف',
  'damaged_store': 'في مخزن التالف',
  'pending_inspection': 'بانتظار الفحص',
  'reserved': 'محجوز',
  'installed': 'مركب',
  'scrapped': 'تم التكهين',
  'lost': 'مفقود',
};

const _operationTypes = <String, String>{
  'movement': 'حركة جهاز / قطعة',
  'transfer': 'أمر نقل',
  'custody': 'تسليم أو استرجاع عهدة',
  'replacement': 'طلب تبديل قطعة',
  'damaged': 'إرجاع تالف',
  'inventory': 'جلسة جرد',
  'employee_clearance': 'إخلاء عهدة موظف',
  'branch_handover': 'تسليم واستلام فرع',
  'temporary_assignment': 'تسليم مؤقت',
  'scrap': 'تنفيذ تكهين',
};

String _operationTypeLabel(String type) =>
    {
      'movement': 'حركة',
      'maintenance': 'صيانة',
      'transfer': 'أمر نقل',
      'replacement': 'تبديل قطعة',
      'damaged': 'تالف',
      'inventory': 'جرد',
      'custody': 'عهدة',
      'employee_clearance': 'إخلاء عهدة',
      'branch_handover': 'تسليم فرع',
      'temporary_assignment': 'عهدة مؤقتة',
      'scrap': 'تكهين',
    }[type] ??
    type;

String _statusLabel(String status) =>
    {
      'available': 'متاح',
      'in_stock': 'في المخزن',
      'assigned_to_employee': 'عهدة موظف',
      'in_branch': 'في فرع',
      'in_maintenance': 'تحت الصيانة',
      'external_maintenance': 'صيانة خارجية',
      'damaged': 'تالف',
      'damaged_store': 'مخزن التالف',
      'pending_inspection': 'بانتظار الفحص',
      'reserved': 'محجوز',
      'installed': 'مركب',
      'scrapped': 'تم التكهين',
      'lost': 'مفقود',
      'draft': 'مسودة',
      'pending_audit': 'بانتظار المراجعة',
      'approved': 'معتمد',
      'in_progress': 'قيد التنفيذ',
      'completed': 'مكتمل',
      'rejected': 'مرفوض',
      'cancelled': 'ملغي',
    }[status] ??
    status;

String _formatDate(DateTime? date) => date == null
    ? '-'
    : DateFormat('yyyy/MM/dd HH:mm', 'ar').format(date.toLocal());
