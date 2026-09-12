import '../../../core/network/api_client.dart';
import '../models/mobile_it_asset_models.dart';

class MobileItAssetsRepository {
  MobileItAssetsRepository(this._client);

  final ApiClient _client;

  Future<MobileItAsset> lookupAsset(String code) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/assets/lookup/${Uri.encodeComponent(code.trim())}',
    );
    return MobileItAsset.fromJson(
      response.data?['asset'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<MobileSparePart> lookupSparePart(String code) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/spare-parts/lookup/${Uri.encodeComponent(code.trim())}',
    );
    return MobileSparePart.fromJson(
      response.data?['sparePart'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<List<MobileInventorySession>> fetchActiveInventorySessions() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/control-records',
      queryParameters: {'type': 'inventory_session', 'status': 'in_progress'},
    );
    return (response.data?['records'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MobileInventorySession.fromJson)
        .toList();
  }

  Future<bool> scanInventory({
    required String sessionId,
    required String code,
    String? foundLocation,
    String? foundEmployee,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/it-assets/inventory-sessions/$sessionId/scan',
      data: {
        'code': code,
        if (foundLocation != null) 'foundLocation': foundLocation,
        if (foundEmployee != null) 'foundEmployee': foundEmployee,
      },
    );
    return response.data?['duplicate'] == true;
  }
}
