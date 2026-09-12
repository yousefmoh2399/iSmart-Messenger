import '../../../core/network/api_client.dart';
import '../models/printer_models.dart';

class MobilePrinterRepository {
  MobilePrinterRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<MobilePrinterOverview> fetchOverview() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/printers/dashboard',
    );
    final body = response.data ?? const <String, dynamic>{};
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    return MobilePrinterOverview.fromJson(data);
  }

  Future<void> fullSync() async {
    await _apiClient.dio.post<Map<String, dynamic>>('/api/printers/sync/full');
  }
}
