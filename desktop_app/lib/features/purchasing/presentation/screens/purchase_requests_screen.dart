import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../purchasing_providers.dart';
import 'create_purchase_request_screen.dart';

class PurchaseRequestsScreen extends ConsumerStatefulWidget {
  const PurchaseRequestsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PurchaseRequestsScreen> createState() =>
      _PurchaseRequestsScreenState();
}

class _PurchaseRequestsScreenState
    extends ConsumerState<PurchaseRequestsScreen> {
  @override
  Widget build(BuildContext context) {
    final prsAsync = ref.watch(purchaseRequestsProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: const Text("طلبات الشراء (Purchase Requests)"),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CreatePurchaseRequestScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text("إنشاء طلب جديد"),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: prsAsync.when(
        data: (prs) {
          if (prs.isEmpty) {
            return const Center(child: Text("لا توجد طلبات شراء مسجلة."));
          }
          return ListView.builder(
            itemCount: prs.length,
            itemBuilder: (context, index) {
              final pr = prs[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(pr['purchaseRequestNo'] ?? 'Unknown PR'),
                  subtitle: Text(
                    "النوع: ${pr['requestType']} | الحالة: ${pr['status']}",
                  ),
                  trailing: Text("الأولوية: ${pr['priority']}"),
                  onTap: () {
                    // Navigate to details screen
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text("حدث خطأ: $err")),
      ),
    );
  }
}
