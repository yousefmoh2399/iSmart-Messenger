import 'package:dio/dio.dart';

class PurchasingRepository {
  final Dio _dio;

  PurchasingRepository(this._dio);

  Future<List<dynamic>> getPurchaseRequests({
    Map<String, dynamic>? query,
  }) async {
    final response = await _dio.get(
      '/api/purchase-requests',
      queryParameters: query,
    );
    return response.data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> getPurchaseRequestById(String id) async {
    final response = await _dio.get('/api/purchase-requests/$id');
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createPurchaseRequest(
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post('/api/purchase-requests', data: data);
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updatePurchaseRequest(
    String id,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.patch('/api/purchase-requests/$id', data: data);
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitPurchaseRequest(String id) async {
    final response = await _dio.post('/api/purchase-requests/$id/submit');
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> itApprove(String id) async {
    final response = await _dio.post('/api/purchase-requests/$id/it-approve');
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> financeApprove(String id) async {
    final response = await _dio.post(
      '/api/purchase-requests/$id/finance-approve',
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> receiveItems(
    String id,
    Map<String, dynamic> data,
  ) async {
    final response = await _dio.post(
      '/api/purchase-requests/$id/receive',
      data: data,
    );
    return response.data['data'] as Map<String, dynamic>;
  }
}
