import '../../../core/network/api_client.dart';
import 'package:dio/dio.dart';
import '../models/it_asset_models.dart';

class ItAssetsRepository {
  ItAssetsRepository(this._client);

  final ApiClient _client;

  Future<ItAssetsOverview> fetchOverview() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/overview',
    );
    return ItAssetsOverview.fromJson(
      response.data?['overview'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<List<ItAsset>> fetchAssets({String? search}) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/assets',
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return (response.data?['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ItAsset.fromJson)
        .toList();
  }

  Future<void> saveAsset(Map<String, dynamic> data, {String? assetId}) async {
    if (assetId == null) {
      await _client.dio.post<void>('/api/it-assets/assets', data: data);
    } else {
      await _client.dio.patch<void>(
        '/api/it-assets/assets/$assetId',
        data: data,
      );
    }
  }

  Future<void> deleteAsset(String assetId, {required String reason}) async {
    await _client.dio.delete<void>(
      '/api/it-assets/assets/$assetId',
      data: {'reason': reason},
    );
  }

  Future<List<ItSparePart>> fetchSpareParts({String? search}) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/spare-parts',
      queryParameters: {
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return (response.data?['spareParts'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ItSparePart.fromJson)
        .toList();
  }

  Future<void> saveSparePart(
    Map<String, dynamic> data, {
    String? sparePartId,
  }) async {
    if (sparePartId == null) {
      await _client.dio.post<void>('/api/it-assets/spare-parts', data: data);
    } else {
      await _client.dio.patch<void>(
        '/api/it-assets/spare-parts/$sparePartId',
        data: data,
      );
    }
  }

  Future<void> deleteSparePart(
    String sparePartId, {
    required String reason,
  }) async {
    await _client.dio.delete<void>(
      '/api/it-assets/spare-parts/$sparePartId',
      data: {'reason': reason},
    );
  }

  Future<List<ItOperation>> fetchOperations({String? type}) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/operations',
      queryParameters: {if (type != null && type.isNotEmpty) 'type': type},
    );
    return (response.data?['operations'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ItOperation.fromJson)
        .toList();
  }

  Future<void> createOperation(Map<String, dynamic> data) async {
    await _client.dio.post<void>('/api/it-assets/operations', data: data);
  }

  Future<void> acknowledgeOperation(
    String operationId, {
    required bool approved,
    required String auditNote,
    required String auditReference,
  }) async {
    await _client.dio.post<void>(
      '/api/it-assets/operations/$operationId/acknowledge',
      data: {
        'approved': approved,
        'auditNote': auditNote,
        'auditReference': auditReference,
      },
    );
  }

  Future<void> completeOperation(
    String operationId, {
    required String solution,
  }) async {
    await _client.dio.post<void>(
      '/api/it-assets/operations/$operationId/complete',
      data: {'solution': solution},
    );
  }

  Future<List<ItAuditEntry>> fetchAuditLog() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/audit-log',
    );
    return (response.data?['logs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ItAuditEntry.fromJson)
        .toList();
  }

  Future<List<ItControlRecord>> fetchControlRecords({String? type}) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/control-records',
      queryParameters: {if (type != null && type.isNotEmpty) 'type': type},
    );
    return (response.data?['records'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ItControlRecord.fromJson)
        .toList();
  }

  Future<ItControlRecord> createControlRecord(Map<String, dynamic> data) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/it-assets/control-records',
      data: data,
    );
    return ItControlRecord.fromJson(
      response.data?['record'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<ItControlRecord> createInventorySession(
    Map<String, dynamic> data,
  ) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/it-assets/inventory-sessions',
      data: data,
    );
    return ItControlRecord.fromJson(
      response.data?['record'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<Map<String, dynamic>> scanInventory(
    String sessionId, {
    required String code,
    String? foundLocation,
    String? foundEmployee,
  }) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/it-assets/inventory-sessions/$sessionId/scan',
      data: {
        'code': code,
        'foundLocation': foundLocation,
        'foundEmployee': foundEmployee,
      },
    );
    return response.data ?? const {};
  }

  Future<void> closeInventory(String sessionId) async {
    await _client.dio.post<void>(
      '/api/it-assets/inventory-sessions/$sessionId/close',
    );
  }

  Future<void> reviewControlRecord(
    String recordId, {
    required bool approved,
    String note = '',
  }) async {
    await _client.dio.post<void>(
      '/api/it-assets/control-records/$recordId/approve',
      data: {'approved': approved, 'note': note},
    );
  }

  Future<void> executeControlRecord(
    String recordId, {
    int? receivedQuantity,
    String? resolution,
  }) async {
    await _client.dio.post<void>(
      '/api/it-assets/control-records/$recordId/execute',
      data: {
        if (receivedQuantity != null) 'receivedQuantity': receivedQuantity,
        if (resolution != null) 'resolution': resolution,
      },
    );
  }

  Future<void> signControlRecord(
    String recordId, {
    required String password,
    required String role,
  }) async {
    await _client.dio.post<void>(
      '/api/it-assets/control-records/$recordId/sign',
      data: {'password': password, 'role': role},
    );
  }

  Future<void> signOperation(
    String operationId, {
    required String password,
    required String role,
  }) async {
    await _client.dio.post<void>(
      '/api/it-assets/operations/$operationId/sign',
      data: {'password': password, 'role': role},
    );
  }

  Future<void> closePeriod(String month, {String notes = ''}) async {
    await _client.dio.post<void>(
      '/api/it-assets/periods/close',
      data: {'month': month, 'notes': notes},
    );
  }

  Future<Map<String, dynamic>> fetchDataQuality() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/data-quality',
    );
    return Map<String, dynamic>.from(
      response.data?['quality'] as Map? ?? const {},
    );
  }

  Future<Map<String, dynamic>> fetchAnalytics() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/analytics',
    );
    return Map<String, dynamic>.from(
      response.data?['analytics'] as Map? ?? const {},
    );
  }

  Future<Map<String, dynamic>> fetchNotifications() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/notifications',
    );
    return Map<String, dynamic>.from(
      response.data?['notifications'] as Map? ?? const {},
    );
  }

  Future<List<Map<String, dynamic>>> fetchReconciliation() async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/reconciliation',
    );
    return (response.data?['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Future<void> uploadAttachment({
    required String entityType,
    required String entityId,
    required String fileName,
    String? filePath,
    List<int>? bytes,
  }) async {
    final file = bytes != null
        ? MultipartFile.fromBytes(bytes, filename: fileName)
        : await MultipartFile.fromFile(filePath!, filename: fileName);
    await _client.dio.post<void>(
      '/api/it-assets/attachments/$entityType/$entityId',
      data: FormData.fromMap({'file': file}),
    );
  }

  Future<List<ItAttachment>> fetchAttachments(
    String entityType,
    String entityId,
  ) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/attachments/$entityType/$entityId',
    );
    return (response.data?['attachments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ItAttachment.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> importExcel({
    required String type,
    required String fileName,
    String? filePath,
    List<int>? bytes,
    required bool apply,
  }) async {
    final file = bytes != null
        ? MultipartFile.fromBytes(bytes, filename: fileName)
        : await MultipartFile.fromFile(filePath!, filename: fileName);
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/it-assets/import/$type',
      queryParameters: {'apply': apply},
      data: FormData.fromMap({'file': file}),
    );
    return response.data ?? const {};
  }

  String operationPdfUrl(String id) =>
      '/api/it-assets/operations/$id/document.pdf';
  String controlRecordPdfUrl(String id) =>
      '/api/it-assets/control-records/$id/document.pdf';
  String assetLabelUrl(String id) => '/api/it-assets/assets/$id/label.pdf';
  String sparePartLabelUrl(String id) =>
      '/api/it-assets/spare-parts/$id/label.pdf';
  Future<Map<String, dynamic>> fetchReportPreview(
    String type, {
    Map<String, dynamic> filters = const {},
  }) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/api/it-assets/reports/$type/preview',
      queryParameters: filters,
    );
    return response.data ?? const {};
  }

  String reportExcelUrl(
    String type, {
    Map<String, dynamic> filters = const {},
  }) => Uri(
    path: '/api/it-assets/reports/$type.xlsx',
    queryParameters: filters.map((key, value) => MapEntry(key, '$value')),
  ).toString();

  String reportPdfUrl(String type, {Map<String, dynamic> filters = const {}}) =>
      Uri(
        path: '/api/it-assets/reports/$type.pdf',
        queryParameters: filters.map((key, value) => MapEntry(key, '$value')),
      ).toString();
  String attachmentUrl(String id) => '/api/it-assets/attachments/file/$id';
}
