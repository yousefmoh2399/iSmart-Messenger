import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../models/it_asset_models.dart';

class ItInventoryManagementTab extends ConsumerStatefulWidget {
  const ItInventoryManagementTab({super.key});

  @override
  ConsumerState<ItInventoryManagementTab> createState() =>
      _ItInventoryManagementTabState();
}

class _ItInventoryManagementTabState
    extends ConsumerState<ItInventoryManagementTab> {
  bool _loading = true;
  List<ItControlRecord> _sessions = const [];
  List<ItControlRecord> _discrepancies = const [];
  String? _selectedSessionId;
  final _scanController = TextEditingController();
  final _locationController = TextEditingController();
  final _employeeController = TextEditingController();
  String? _scanResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scanController.dispose();
    _locationController.dispose();
    _employeeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final repository = ref.read(itAssetsRepositoryProvider);
    final results = await Future.wait([
      repository.fetchControlRecords(type: 'inventory_session'),
      repository.fetchControlRecords(type: 'discrepancy'),
    ]);
    if (!mounted) return;
    setState(() {
      _sessions = results[0];
      _discrepancies = results[1];
      final active = _sessions.where((entry) => entry.status == 'in_progress');
      _selectedSessionId ??= active.isEmpty ? null : active.first.id;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final activeSessions = _sessions
        .where((entry) => entry.status == 'in_progress')
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'الجرد بالـ QR / Barcode',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (user?.canManageItInventory == true)
              FilledButton.icon(
                onPressed: _createSession,
                icon: const Icon(Icons.add_rounded),
                label: const Text('جلسة جرد جديدة'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        activeSessions.any(
                          (entry) => entry.id == _selectedSessionId,
                        )
                        ? _selectedSessionId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'جلسة الجرد النشطة',
                    ),
                    items: activeSessions
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.id,
                            child: Text(
                              '${entry.recordNumber} - ${entry.title}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedSessionId = value),
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _scanController,
                    autofocus: true,
                    onSubmitted: (_) => _scan(),
                    decoration: const InputDecoration(
                      labelText: 'امسح QR أو اكتب كود الجهاز / السيريال',
                      prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'المكان الفعلي',
                    ),
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _employeeController,
                    decoration: const InputDecoration(
                      labelText: 'الموظف الفعلي',
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _selectedSessionId == null ? null : _scan,
                  icon: const Icon(Icons.center_focus_strong_rounded),
                  label: const Text('تسجيل المسح'),
                ),
                OutlinedButton.icon(
                  onPressed: _selectedSessionId == null ? null : _closeSession,
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('إغلاق الجرد وإنتاج الفروق'),
                ),
              ],
            ),
          ),
        ),
        if (_scanResult != null) ...[
          const SizedBox(height: 10),
          Text(
            _scanResult!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'جلسات الجرد (${_sessions.length})',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ..._sessions.map(
          (session) => Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_rounded),
              title: Text('${session.recordNumber} • ${session.title}'),
              subtitle: Text(
                '${session.branchName} • ${session.location} • '
                'متوقع: ${(session.data['expectedAssetIds'] as List?)?.length ?? 0} • '
                'تم مسحه: ${(session.data['scannedAssetIds'] as List?)?.length ?? 0}',
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _AdvancedStatusChip(session.status),
                  IconButton(
                    tooltip: 'PDF',
                    onPressed: () => _downloadPdf(session),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'فروق الجرد (${_discrepancies.length})',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ..._discrepancies.map(
          (record) => Card(
            child: ListTile(
              leading: const Icon(
                Icons.report_problem_outlined,
                color: Colors.deepOrange,
              ),
              title: Text('${record.recordNumber} • ${record.title}'),
              subtitle: Text(
                '${record.asset?.assetCode ?? ''} • ${record.reason}',
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _AdvancedStatusChip(record.status),
                  if (user?.canManageItInventory == true &&
                      record.status == 'open')
                    PopupMenuButton<String>(
                      tooltip: 'حل الفرق',
                      onSelected: (resolution) =>
                          _resolveDiscrepancy(record, resolution),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'corrected_movement',
                          child: Text('إنشاء / تسجيل حركة تصحيح'),
                        ),
                        PopupMenuItem(
                          value: 'accepted_difference',
                          child: Text('قبول الفرق'),
                        ),
                        PopupMenuItem(
                          value: 'mark_lost',
                          child: Text('تسجيل الجهاز مفقود'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createSession() async {
    final title = TextEditingController(text: 'جرد دوري');
    final branch = TextEditingController();
    final location = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إنشاء جلسة جرد'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'اسم الجلسة'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: branch,
                decoration: const InputDecoration(labelText: 'الفرع'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: location,
                decoration: const InputDecoration(labelText: 'المخزن / المكان'),
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
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final session = await ref
          .read(itAssetsRepositoryProvider)
          .createInventorySession({
            'title': title.text.trim(),
            'branchName': branch.text.trim(),
            'location': location.text.trim(),
          });
      _selectedSessionId = session.id;
      await _load();
    }
    title.dispose();
    branch.dispose();
    location.dispose();
  }

  Future<void> _scan() async {
    final code = _scanController.text.trim();
    if (_selectedSessionId == null || code.isEmpty) return;
    try {
      final result = await ref
          .read(itAssetsRepositoryProvider)
          .scanInventory(
            _selectedSessionId!,
            code: code,
            foundLocation: _locationController.text.trim(),
            foundEmployee: _employeeController.text.trim(),
          );
      final asset = result['asset'] as Map?;
      setState(() {
        _scanResult =
            'تم تسجيل ${(asset?['assetCode'] ?? code)}'
            '${result['duplicate'] == true ? ' — مسح مكرر' : ''}';
        _scanController.clear();
      });
      await _load();
    } catch (error) {
      setState(() => _scanResult = error.toString());
    }
  }

  Future<void> _closeSession() async {
    await ref
        .read(itAssetsRepositoryProvider)
        .closeInventory(_selectedSessionId!);
    _selectedSessionId = null;
    await _load();
  }

  Future<void> _downloadPdf(ItControlRecord record) async {
    final repository = ref.read(itAssetsRepositoryProvider);
    await ref.read(desktopFileSaveServiceProvider).executeSaveJob({
      'fileName': '${record.recordNumber}.pdf',
      'mimeType': 'application/pdf',
      'downloadUrl': repository.controlRecordPdfUrl(record.id),
    });
  }

  Future<void> _resolveDiscrepancy(
    ItControlRecord record,
    String resolution,
  ) async {
    await ref
        .read(itAssetsRepositoryProvider)
        .executeControlRecord(record.id, resolution: resolution);
    await _load();
  }
}

class ItGovernanceTab extends ConsumerStatefulWidget {
  const ItGovernanceTab({super.key});

  @override
  ConsumerState<ItGovernanceTab> createState() => _ItGovernanceTabState();
}

class _ItGovernanceTabState extends ConsumerState<ItGovernanceTab> {
  bool _loading = true;
  List<ItControlRecord> _records = const [];
  List<ItAsset> _assets = const [];
  List<ItSparePart> _parts = const [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final repository = ref.read(itAssetsRepositoryProvider);
    final results = await Future.wait<dynamic>([
      repository.fetchControlRecords(),
      repository.fetchAssets(),
      repository.fetchSpareParts(),
    ]);
    final records = results[0] as List<ItControlRecord>;
    if (!mounted) return;
    setState(() {
      _records = records
          .where(
            (entry) => !const [
              'inventory_session',
              'discrepancy',
              'notification',
            ].contains(entry.recordType),
          )
          .toList();
      _assets = results[1] as List<ItAsset>;
      _parts = results[2] as List<ItSparePart>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;
    final visible = _filter == 'all'
        ? _records
        : _records.where((entry) => entry.recordType == _filter).toList();
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String>(
                  initialValue: _filter,
                  decoration: const InputDecoration(labelText: 'نوع المستند'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                    DropdownMenuItem(
                      value: 'correction',
                      child: Text('طلبات التصحيح'),
                    ),
                    DropdownMenuItem(
                      value: 'damaged_inspection',
                      child: Text('فحص التالف'),
                    ),
                    DropdownMenuItem(
                      value: 'scrap_request',
                      child: Text('طلبات التكهين'),
                    ),
                    DropdownMenuItem(
                      value: 'vendor',
                      child: Text('الموردون والضمان'),
                    ),
                    DropdownMenuItem(
                      value: 'purchase_request',
                      child: Text('طلبات الشراء'),
                    ),
                    DropdownMenuItem(
                      value: 'workflow_rule',
                      child: Text('قواعد الاعتماد'),
                    ),
                    DropdownMenuItem(
                      value: 'period_closure',
                      child: Text('الفترات المغلقة'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _filter = value ?? 'all'),
                ),
              ),
              if (user?.canExecuteItAssets == true ||
                  user?.canInspectDamagedItAssets == true ||
                  user?.canManageItProcurement == true ||
                  user?.canManageItSettings == true)
                FilledButton.icon(
                  onPressed: _createRecord,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('مستند رقابي جديد'),
                ),
              if (user?.canCloseItPeriods == true)
                OutlinedButton.icon(
                  onPressed: _closePeriod,
                  icon: const Icon(Icons.event_busy_outlined),
                  label: const Text('قفل فترة شهرية'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('لا توجد مستندات رقابية.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final record = visible[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(_recordIcon(record.recordType)),
                        title: Text('${record.recordNumber} • ${record.title}'),
                        subtitle: Text(
                          '${_recordTypeLabel(record.recordType)} • '
                          '${record.createdByName} • ${record.reason}',
                        ),
                        trailing: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (record.locked)
                              const Tooltip(
                                message: 'موقع ومقفل',
                                child: Icon(Icons.verified_user_outlined),
                              ),
                            _AdvancedStatusChip(record.status),
                            IconButton(
                              tooltip: 'PDF',
                              onPressed: () => _downloadRecordPdf(record),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                            ),
                            IconButton(
                              tooltip: 'توقيع إلكتروني',
                              onPressed: () => _signRecord(record),
                              icon: const Icon(Icons.draw_outlined),
                            ),
                            IconButton(
                              tooltip: 'المرفقات',
                              onPressed: () => _attachments(record),
                              icon: const Icon(Icons.attach_file_rounded),
                            ),
                            if (record.status == 'approved')
                              IconButton(
                                tooltip: 'تنفيذ المستند',
                                onPressed: () => _execute(record),
                                icon: const Icon(Icons.task_alt_rounded),
                              ),
                            if (user?.canAuditItAssets == true &&
                                !const [
                                  'approved',
                                  'rejected',
                                  'closed',
                                ].contains(record.status))
                              PopupMenuButton<bool>(
                                tooltip: 'المراجعة',
                                onSelected: (approved) =>
                                    _review(record, approved),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: true,
                                    child: Text('اعتماد'),
                                  ),
                                  PopupMenuItem(
                                    value: false,
                                    child: Text('رفض'),
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
    );
  }

  Future<void> _createRecord() async {
    var type = 'correction';
    final title = TextEditingController();
    final reason = TextEditingController();
    final notes = TextEditingController();
    final branch = TextEditingController();
    final location = TextEditingController();
    final data = TextEditingController();
    final requestedQuantity = TextEditingController();
    String? assetId;
    String? sparePartId;
    var workflowOperationType = 'movement';
    var needsAudit = true;
    var needsAttachment = false;
    var needsSignature = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('إنشاء مستند رقابي'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'النوع'),
                    items: const [
                      DropdownMenuItem(
                        value: 'correction',
                        child: Text('طلب تصحيح'),
                      ),
                      DropdownMenuItem(
                        value: 'damaged_inspection',
                        child: Text('فحص تالف'),
                      ),
                      DropdownMenuItem(
                        value: 'scrap_request',
                        child: Text('طلب تكهين'),
                      ),
                      DropdownMenuItem(
                        value: 'vendor',
                        child: Text('مورد / ضمان'),
                      ),
                      DropdownMenuItem(
                        value: 'purchase_request',
                        child: Text('طلب شراء'),
                      ),
                      DropdownMenuItem(
                        value: 'workflow_rule',
                        child: Text('قاعدة اعتماد'),
                      ),
                    ],
                    onChanged: (value) =>
                        setLocalState(() => type = value ?? type),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: assetId,
                    decoration: const InputDecoration(
                      labelText: 'الجهاز المرتبط',
                    ),
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: sparePartId,
                    decoration: const InputDecoration(
                      labelText: 'قطعة الغيار المرتبطة',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('بدون قطعة'),
                      ),
                      ..._parts.map(
                        (part) => DropdownMenuItem(
                          value: part.id,
                          child: Text('${part.partCode} - ${part.name}'),
                        ),
                      ),
                    ],
                    onChanged: (value) => sparePartId = value,
                  ),
                  if (type == 'purchase_request') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: requestedQuantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الكمية المطلوبة',
                      ),
                    ),
                  ],
                  if (type == 'workflow_rule') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: workflowOperationType,
                      decoration: const InputDecoration(
                        labelText: 'نوع الحركة',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'movement',
                          child: Text('حركة'),
                        ),
                        DropdownMenuItem(
                          value: 'transfer',
                          child: Text('أمر نقل'),
                        ),
                        DropdownMenuItem(
                          value: 'replacement',
                          child: Text('تبديل قطعة'),
                        ),
                        DropdownMenuItem(
                          value: 'damaged',
                          child: Text('إرجاع تالف'),
                        ),
                        DropdownMenuItem(value: 'scrap', child: Text('تكهين')),
                        DropdownMenuItem(value: 'custody', child: Text('عهدة')),
                      ],
                      onChanged: (value) => setLocalState(
                        () => workflowOperationType =
                            value ?? workflowOperationType,
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('تحتاج إقرار / اعتماد المراجعة'),
                      value: needsAudit,
                      onChanged: (value) =>
                          setLocalState(() => needsAudit = value),
                    ),
                    SwitchListTile(
                      title: const Text('المرفق إجباري'),
                      value: needsAttachment,
                      onChanged: (value) =>
                          setLocalState(() => needsAttachment = value),
                    ),
                    SwitchListTile(
                      title: const Text('التوقيع الإلكتروني إجباري'),
                      value: needsSignature,
                      onChanged: (value) =>
                          setLocalState(() => needsSignature = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'السبب'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: branch,
                    decoration: const InputDecoration(labelText: 'الفرع'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(labelText: 'المكان'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: data,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText:
                          'القيم القديمة والجديدة / التشخيص / بيانات المورد',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'ملاحظات'),
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(itAssetsRepositoryProvider).createControlRecord({
        'recordType': type,
        'title': title.text.trim(),
        'reason': reason.text.trim(),
        'branchName': branch.text.trim(),
        'location': location.text.trim(),
        'notes': notes.text.trim(),
        'status': const ['vendor', 'workflow_rule'].contains(type)
            ? 'active'
            : 'pending_approval',
        'assetId': assetId,
        'sparePartId': sparePartId,
        'data': {
          'details': data.text.trim(),
          if (type == 'purchase_request')
            'requestedQuantity':
                int.tryParse(requestedQuantity.text.trim()) ?? 0,
          if (type == 'workflow_rule') 'operationType': workflowOperationType,
          if (type == 'workflow_rule') 'needsAuditAcknowledgement': needsAudit,
          if (type == 'workflow_rule') 'needsAttachment': needsAttachment,
          if (type == 'workflow_rule') 'needsDigitalSignature': needsSignature,
        },
      });
      await _load();
    }
    title.dispose();
    reason.dispose();
    notes.dispose();
    branch.dispose();
    location.dispose();
    data.dispose();
    requestedQuantity.dispose();
  }

  Future<void> _review(ItControlRecord record, bool approved) async {
    await ref
        .read(itAssetsRepositoryProvider)
        .reviewControlRecord(record.id, approved: approved);
    await _load();
  }

  Future<void> _execute(ItControlRecord record) async {
    int? quantity;
    String? resolution;
    if (record.recordType == 'purchase_request') {
      final controller = TextEditingController(
        text: '${record.data['requestedQuantity'] ?? ''}',
      );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('استلام طلب الشراء'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'الكمية المستلمة'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استلام'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        controller.dispose();
        return;
      }
      quantity = int.tryParse(controller.text);
      controller.dispose();
    }
    if (record.recordType == 'discrepancy') {
      resolution = 'mark_lost';
    }
    await ref
        .read(itAssetsRepositoryProvider)
        .executeControlRecord(
          record.id,
          receivedQuantity: quantity,
          resolution: resolution,
        );
    await _load();
  }

  Future<void> _attachments(ItControlRecord record) async {
    var attachments = await ref
        .read(itAssetsRepositoryProvider)
        .fetchAttachments('control_record', record.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('مرفقات ${record.recordNumber}'),
          content: SizedBox(
            width: 560,
            height: 360,
            child: attachments.isEmpty
                ? const Center(child: Text('لا توجد مرفقات.'))
                : ListView(
                    children: attachments
                        .map(
                          (entry) => ListTile(
                            leading: const Icon(Icons.attach_file_rounded),
                            title: Text(entry.originalName),
                            subtitle: Text(entry.uploadedByName),
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
                      entityType: 'control_record',
                      entityId: record.id,
                      fileName: file.name,
                      filePath: file.path,
                      bytes: file.bytes,
                    );
                attachments = await ref
                    .read(itAssetsRepositoryProvider)
                    .fetchAttachments('control_record', record.id);
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

  Future<void> _signRecord(ItControlRecord record) async {
    final password = TextEditingController();
    final role = TextEditingController(text: 'المعتمد');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('توقيع ${record.recordNumber}'),
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
            child: const Text('توقيع وقفل'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(itAssetsRepositoryProvider)
          .signControlRecord(
            record.id,
            password: password.text,
            role: role.text,
          );
      await _load();
    }
    password.dispose();
    role.dispose();
  }

  Future<void> _closePeriod() async {
    final month = TextEditingController(
      text:
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
    );
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('قفل فترة شهرية'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: month,
                decoration: const InputDecoration(labelText: 'الشهر YYYY-MM'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
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
            child: const Text('قفل الفترة'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(itAssetsRepositoryProvider)
          .closePeriod(month.text.trim(), notes: notes.text.trim());
      await _load();
    }
    month.dispose();
    notes.dispose();
  }

  Future<void> _downloadRecordPdf(ItControlRecord record) async {
    final repository = ref.read(itAssetsRepositoryProvider);
    await ref.read(desktopFileSaveServiceProvider).executeSaveJob({
      'fileName': '${record.recordNumber}.pdf',
      'mimeType': 'application/pdf',
      'downloadUrl': repository.controlRecordPdfUrl(record.id),
    });
  }
}

class ItReportsAndQualityTab extends ConsumerStatefulWidget {
  const ItReportsAndQualityTab({super.key});

  @override
  ConsumerState<ItReportsAndQualityTab> createState() =>
      _ItReportsAndQualityTabState();
}

class _ItReportsAndQualityTabState
    extends ConsumerState<ItReportsAndQualityTab> {
  bool _loading = true;
  Map<String, dynamic> _quality = const {};
  Map<String, dynamic> _analytics = const {};
  Map<String, dynamic> _notifications = const {};
  List<Map<String, dynamic>> _reconciliation = const [];
  String _reportType = 'assets';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _branchFilter = TextEditingController();
  final _statusFilter = TextEditingController();
  Map<String, dynamic> _reportPreview = const {};
  bool _reportLoading = false;

  static const _reportTypes = <String, String>{
    'assets': 'الأجهزة والأصول',
    'spare-parts': 'قطع الغيار والمخزون',
    'operations': 'الحركات',
    'maintenance': 'الصيانة',
    'inventory': 'الجرد والفروقات',
    'damaged': 'التالف والتكهين',
    'procurement': 'الموردون والمشتريات',
    'audit': 'سجل العمليات',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _branchFilter.dispose();
    _statusFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final repository = ref.read(itAssetsRepositoryProvider);
    final user = ref.read(authControllerProvider).valueOrNull;
    final results = await Future.wait<dynamic>([
      repository.fetchDataQuality(),
      repository.fetchAnalytics(),
      repository.fetchNotifications(),
      if (user?.canAuditItAssets == true)
        repository.fetchReconciliation()
      else
        Future<List<Map<String, dynamic>>>.value(const []),
    ]);
    if (!mounted) return;
    setState(() {
      _quality = results[0] as Map<String, dynamic>;
      _analytics = results[1] as Map<String, dynamic>;
      _notifications = results[2] as Map<String, dynamic>;
      _reconciliation = results[3] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final qualityCards = <(String, Object?, IconData)>[
      (
        'أجهزة بدون سيريال',
        _quality['assetsWithoutSerial'],
        Icons.numbers_outlined,
      ),
      (
        'أجهزة بدون مكان',
        _quality['assetsWithoutLocation'],
        Icons.location_off_outlined,
      ),
      (
        'أجهزة بدون عهدة',
        _quality['assetsWithoutCustodian'],
        Icons.person_off_outlined,
      ),
      (
        'قطع تحت الحد الأدنى',
        _quality['sparePartsBelowMinimum'],
        Icons.trending_down_rounded,
      ),
      (
        'حركات بدون مستلم',
        _quality['movementsWithoutReceiver'],
        Icons.rule_folder_outlined,
      ),
      (
        'لم تظهر في آخر جرد',
        _quality['assetsNotScanned'],
        Icons.qr_code_2_outlined,
      ),
      ('Serial مكرر', _quality['duplicateSerials'], Icons.copy_all_outlined),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildReportsPanel(),
        const SizedBox(height: 24),
        const Text(
          'جودة البيانات',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: qualityCards
              .map(
                (item) => _QualityCard(
                  label: item.$1,
                  value: item.$2?.toString() ?? '0',
                  icon: item.$3,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text(
          'التنبيهات',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _QualityCard(
              label: 'مخزون منخفض',
              value: '${(_notifications['lowStock'] as List?)?.length ?? 0}',
              icon: Icons.inventory_outlined,
            ),
            _QualityCard(
              label: 'ضمان ينتهي خلال 30 يوم',
              value:
                  '${(_notifications['expiringWarranty'] as List?)?.length ?? 0}',
              icon: Icons.shield_outlined,
            ),
            _QualityCard(
              label: 'صيانة متأخرة',
              value:
                  '${(_notifications['overdueMaintenance'] as List?)?.length ?? 0}',
              icon: Icons.timer_off_outlined,
            ),
            _QualityCard(
              label: 'بانتظار المراجعة',
              value:
                  '${(_notifications['pendingAudit'] as List?)?.length ?? 0}',
              icon: Icons.fact_check_outlined,
            ),
            _QualityCard(
              label: 'عهد مؤقتة مستحقة',
              value:
                  '${(_notifications['temporaryReturns'] as List?)?.length ?? 0}',
              icon: Icons.event_repeat_outlined,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'تحليل أسباب التلف والمخاطر',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'أسباب الأعطال: ${_analytics['rootCauses'] ?? {}}\n'
              'مخاطر الفروع: ${_analytics['branchRisk'] ?? []}\n'
              'مخاطر الموظفين: ${_analytics['employeeRisk'] ?? []}',
            ),
          ),
        ),
        if (_reconciliation.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'مطابقة IT مع المراجعة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ..._reconciliation
              .take(100)
              .map(
                (item) => ListTile(
                  leading: Icon(
                    item['result'] == 'matched'
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                  ),
                  title: Text('${item['documentNumber']}'),
                  subtitle: Text(
                    'IT: ${item['itStatus']} • Audit: ${item['auditStatus']}',
                  ),
                  trailing: Text('${item['result']}'),
                ),
              ),
        ],
      ],
    );
  }

  Map<String, dynamic> get _reportFilters => {
    if (_dateFrom != null)
      'dateFrom': _dateFrom!.toIso8601String().split('T').first,
    if (_dateTo != null) 'dateTo': _dateTo!.toIso8601String().split('T').first,
    if (_branchFilter.text.trim().isNotEmpty)
      'branch': _branchFilter.text.trim(),
    if (_statusFilter.text.trim().isNotEmpty)
      'status': _statusFilter.text.trim(),
  };

  Widget _buildReportsPanel() {
    final rows = (_reportPreview['rows'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined),
                SizedBox(width: 8),
                Text(
                  'مركز التقارير والتصدير',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    initialValue: _reportType,
                    decoration: const InputDecoration(
                      labelText: 'نوع التقرير',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                    items: _reportTypes.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _reportType = value ?? _reportType),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: TextField(
                    controller: _branchFilter,
                    decoration: const InputDecoration(
                      labelText: 'الفرع',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: TextField(
                    controller: _statusFilter,
                    decoration: const InputDecoration(
                      labelText: 'الحالة',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickReportDate(from: true),
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    _dateFrom == null
                        ? 'من تاريخ'
                        : _dateFrom!.toIso8601String().split('T').first,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickReportDate(from: false),
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                    _dateTo == null
                        ? 'إلى تاريخ'
                        : _dateTo!.toIso8601String().split('T').first,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _reportLoading ? null : _previewReport,
                  icon: _reportLoading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.preview_outlined),
                  label: const Text('معاينة التقرير'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _export(_reportType),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('تصدير Excel'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _exportPdf(_reportType),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('تصدير PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _import(false),
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('معاينة استيراد Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _import(true),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('تنفيذ الاستيراد'),
                ),
              ],
            ),
            if (_reportPreview.isNotEmpty) ...[
              const Divider(height: 32),
              Text(
                '${_reportPreview['title'] ?? 'التقرير'} — الإجمالي: ${_reportPreview['summary']?['total'] ?? rows.length}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('لا توجد بيانات مطابقة للفلاتر.')),
                )
              else
                ...rows
                    .take(25)
                    .map(
                      (row) => Card.outlined(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Wrap(
                            spacing: 18,
                            runSpacing: 6,
                            children: row.entries
                                .where(
                                  (entry) =>
                                      entry.value != null &&
                                      entry.value.toString().isNotEmpty &&
                                      !entry.key.startsWith('_') &&
                                      entry.value is! Map &&
                                      entry.value is! List,
                                )
                                .take(8)
                                .map(
                                  (entry) => Text(
                                    '${entry.key}: ${entry.value}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ),
              if (_reportPreview['truncated'] == true)
                const Text(
                  'المعاينة تعرض أول 250 سجلًا؛ ملف التصدير يحتوي على كل النتائج.',
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickReportDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: (from ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (from) {
        _dateFrom = selected;
      } else {
        _dateTo = selected;
      }
    });
  }

  Future<void> _previewReport() async {
    setState(() => _reportLoading = true);
    try {
      final preview = await ref
          .read(itAssetsRepositoryProvider)
          .fetchReportPreview(_reportType, filters: _reportFilters);
      if (mounted) setState(() => _reportPreview = preview);
    } finally {
      if (mounted) setState(() => _reportLoading = false);
    }
  }

  Future<void> _export(String type) async {
    final repository = ref.read(itAssetsRepositoryProvider);
    await ref.read(desktopFileSaveServiceProvider).executeSaveJob({
      'fileName': 'it-$type-report.xlsx',
      'mimeType':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'downloadUrl': repository.reportExcelUrl(type, filters: _reportFilters),
    });
  }

  Future<void> _exportPdf(String type) async {
    final repository = ref.read(itAssetsRepositoryProvider);
    await ref.read(desktopFileSaveServiceProvider).executeSaveJob({
      'fileName': 'it-$type-report.pdf',
      'mimeType': 'application/pdf',
      'downloadUrl': repository.reportPdfUrl(type, filters: _reportFilters),
    });
  }

  Future<void> _import(bool apply) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    if (!mounted) return;
    var type = 'assets';
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(apply ? 'تنفيذ الاستيراد' : 'معاينة الاستيراد'),
        content: StatefulBuilder(
          builder: (context, setLocalState) => DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'نوع البيانات'),
            items: const [
              DropdownMenuItem(value: 'assets', child: Text('الأجهزة')),
              DropdownMenuItem(value: 'spare-parts', child: Text('قطع الغيار')),
            ],
            onChanged: (value) => setLocalState(() => type = value ?? type),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, type),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    final response = await ref
        .read(itAssetsRepositoryProvider)
        .importExcel(
          type: selected,
          fileName: file.name,
          filePath: file.path,
          bytes: file.bytes,
          apply: apply,
        );
    if (!mounted) return;
    final preview = response['preview'] as Map? ?? const {};
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'صالح: ${preview['validRows'] ?? 0} • أخطاء: ${preview['invalidRows'] ?? 0}'
          '${response['applied'] == true ? ' • تم الحفظ' : ''}',
        ),
      ),
    );
    if (response['applied'] == true) await _load();
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
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
        ),
      ],
    ),
  );
}

class _AdvancedStatusChip extends StatelessWidget {
  const _AdvancedStatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) =>
      Chip(label: Text(status), visualDensity: VisualDensity.compact);
}

IconData _recordIcon(String type) => switch (type) {
  'correction' => Icons.edit_note_outlined,
  'damaged_inspection' => Icons.biotech_outlined,
  'scrap_request' => Icons.delete_sweep_outlined,
  'vendor' => Icons.storefront_outlined,
  'purchase_request' => Icons.shopping_cart_checkout_outlined,
  'workflow_rule' => Icons.account_tree_outlined,
  'period_closure' => Icons.event_busy_outlined,
  _ => Icons.description_outlined,
};

String _recordTypeLabel(String type) => switch (type) {
  'correction' => 'طلب تصحيح',
  'damaged_inspection' => 'فحص تالف',
  'scrap_request' => 'طلب تكهين',
  'vendor' => 'مورد / ضمان',
  'purchase_request' => 'طلب شراء',
  'workflow_rule' => 'قاعدة اعتماد',
  'period_closure' => 'قفل فترة',
  _ => type,
};
