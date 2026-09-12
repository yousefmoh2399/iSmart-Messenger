import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/providers.dart';
import 'data/purchasing_repository.dart';

final purchasingRepositoryProvider = Provider<PurchasingRepository>((ref) {
  final client = ref.watch(authenticatedApiClientProvider);
  return PurchasingRepository(client.dio);
});

final purchaseRequestsProvider =
    FutureProvider.family<List<dynamic>, Map<String, dynamic>?>((
      ref,
      query,
    ) async {
      final repo = ref.watch(purchasingRepositoryProvider);
      return repo.getPurchaseRequests(query: query);
    });

final purchaseRequestDetailsProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
      final repo = ref.watch(purchasingRepositoryProvider);
      return repo.getPurchaseRequestById(id);
    });
