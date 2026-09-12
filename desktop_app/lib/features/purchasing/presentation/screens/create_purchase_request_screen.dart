import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../purchasing_providers.dart';

class CreatePurchaseRequestScreen extends ConsumerStatefulWidget {
  const CreatePurchaseRequestScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CreatePurchaseRequestScreen> createState() =>
      _CreatePurchaseRequestScreenState();
}

class _CreatePurchaseRequestScreenState
    extends ConsumerState<CreatePurchaseRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  String _requestType = 'New Assets';
  String _requestedForType = 'Main IT Store';
  String _priority = 'Medium';
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<Map<String, dynamic>> _items = [];

  bool _isSubmitting = false;

  void _addItem() {
    setState(() {
      _items.add({
        'itemType': 'Asset',
        'itemName': '',
        'requestedQuantity': 1,
        'estimatedUnitPrice': 0,
        'notes': '',
      });
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("يجب إضافة عنصر واحد على الأقل للطلب.")),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(purchasingRepositoryProvider);
      await repo.createPurchaseRequest({
        'requestType': _requestType,
        'requestedForType': _requestedForType,
        'priority': _priority,
        'reason': _reasonController.text.isEmpty
            ? "No reason specified"
            : _reasonController.text,
        'notes': _notesController.text,
        'items': _items,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم إنشاء طلب الشراء بنجاح!")),
      );
      ref.invalidate(purchaseRequestsProvider);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("إنشاء طلب شراء جديد"),
        actions: [
          if (_isSubmitting)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save),
              label: const Text("حفظ كمسودة (Draft)"),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Header Info Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "المعلومات الأساسية",
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _requestType,
                            decoration: const InputDecoration(
                              labelText: "نوع الطلب (Request Type)",
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'New Assets',
                                child: Text('أجهزة جديدة (New Assets)'),
                              ),
                              DropdownMenuItem(
                                value: 'Spare Parts',
                                child: Text('قطع غيار (Spare Parts)'),
                              ),
                              DropdownMenuItem(
                                value: 'Consumables',
                                child: Text('مستهلكات (Consumables)'),
                              ),
                              DropdownMenuItem(
                                value: 'Replacement Requirement',
                                child: Text(
                                  'استبدال (Replacement Requirement)',
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'Maintenance Requirement',
                                child: Text('صيانة (Maintenance Requirement)'),
                              ),
                              DropdownMenuItem(
                                value: 'Stock Refill',
                                child: Text(
                                  'إعادة تعبئة المخزون (Stock Refill)',
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'Branch Requirement',
                                child: Text('احتياج فرع (Branch Requirement)'),
                              ),
                              DropdownMenuItem(
                                value: 'Project Requirement',
                                child: Text(
                                  'احتياج مشروع (Project Requirement)',
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'Other',
                                child: Text('أخرى (Other)'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _requestType = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _requestedForType,
                            decoration: const InputDecoration(
                              labelText: "مطلوب لصالح (Requested For)",
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Main IT Store',
                                child: Text('مخزن الـ IT الرئيسي'),
                              ),
                              DropdownMenuItem(
                                value: 'Branch',
                                child: Text('فرع (Branch)'),
                              ),
                              DropdownMenuItem(
                                value: 'Employee',
                                child: Text('موظف (Employee)'),
                              ),
                              DropdownMenuItem(
                                value: 'Maintenance',
                                child: Text('صيانة (Maintenance)'),
                              ),
                              DropdownMenuItem(
                                value: 'Project',
                                child: Text('مشروع (Project)'),
                              ),
                              DropdownMenuItem(
                                value: 'General Stock',
                                child: Text('مخزون عام (General Stock)'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _requestedForType = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _priority,
                            decoration: const InputDecoration(
                              labelText: "الأولوية (Priority)",
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Low',
                                child: Text('منخفضة (Low)'),
                              ),
                              DropdownMenuItem(
                                value: 'Medium',
                                child: Text('متوسطة (Medium)'),
                              ),
                              DropdownMenuItem(
                                value: 'High',
                                child: Text('عالية (High)'),
                              ),
                              DropdownMenuItem(
                                value: 'Critical',
                                child: Text('عاجلة جداً (Critical)'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _priority = v!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _reasonController,
                      decoration: const InputDecoration(
                        labelText: "سبب الطلب (Reason - إلزامي)",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "مطلوب" : null,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: "ملاحظات إضافية (اختياري)",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Items Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "عناصر الطلب (Items)",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ElevatedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text("إضافة عنصر"),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_items.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text("اضغط على 'إضافة عنصر' للبدء في تعبئة الطلب."),
                ),
              )
            else
              ..._items.asMap().entries.map((entry) {
                int idx = entry.key;
                var item = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: item['itemType'],
                            decoration: const InputDecoration(
                              labelText: "النوع",
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Asset',
                                child: Text('أصل / جهاز (Asset)'),
                              ),
                              DropdownMenuItem(
                                value: 'Spare Part',
                                child: Text('قطعة غيار (Spare Part)'),
                              ),
                              DropdownMenuItem(
                                value: 'Consumable',
                                child: Text('مستهلكات (Consumable)'),
                              ),
                              DropdownMenuItem(
                                value: 'Service',
                                child: Text('خدمة (Service)'),
                              ),
                              DropdownMenuItem(
                                value: 'Other',
                                child: Text('أخرى (Other)'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => item['itemType'] = v!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: TextFormField(
                            initialValue: item['itemName'],
                            decoration: const InputDecoration(
                              labelText: "اسم العنصر / المواصفات",
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => item['itemName'] = v,
                            validator: (v) => v!.isEmpty ? "مطلوب" : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            initialValue: item['requestedQuantity'].toString(),
                            decoration: const InputDecoration(
                              labelText: "الكمية المطلوبة",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => item['requestedQuantity'] =
                                int.tryParse(v) ?? 1,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: item['estimatedUnitPrice'].toString(),
                            decoration: const InputDecoration(
                              labelText: "السعر التقديري (للوحدة)",
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              item['estimatedUnitPrice'] =
                                  double.tryParse(v) ?? 0.0;
                              item['estimatedTotalPrice'] =
                                  item['estimatedUnitPrice'] *
                                  item['requestedQuantity'];
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeItem(idx),
                          tooltip: "إزالة",
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}
