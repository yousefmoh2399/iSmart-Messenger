import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/providers/providers.dart';
import '../models/report_template_models.dart';

final reportTemplateRepositoryProvider = Provider<ReportTemplateRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ReportTemplateRepository(apiClient);
});

class ReportTemplateRepository {
  ReportTemplateRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ReportTemplate>> fetchTemplates(String reportType) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/report-templates',
      queryParameters: {'reportType': reportType},
    );

    final data = _extractData(response.data);
    final rawList = data['templates'] as List<dynamic>? ?? [];
    return rawList
        .map((t) => ReportTemplate.fromMap(t as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReportColumn>> fetchAvailableColumns(String reportType) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/report-templates/available-columns',
      queryParameters: {'reportType': reportType},
    );

    final data = _extractData(response.data);
    final rawList = data['columns'] as List<dynamic>? ?? [];
    return rawList
        .map((c) => ReportColumn.fromMap(c as Map<String, dynamic>))
        .toList();
  }

  Future<ReportTemplate> createTemplate(ReportTemplate template) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/report-templates',
      data: template.toMap(),
    );

    final data = _extractData(response.data);
    return ReportTemplate.fromMap(data['template'] as Map<String, dynamic>);
  }

  Future<ReportTemplate> updateTemplate(String id, ReportTemplate template) async {
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/report-templates/$id',
      data: template.toMap(),
    );

    final data = _extractData(response.data);
    return ReportTemplate.fromMap(data['template'] as Map<String, dynamic>);
  }

  Future<void> deleteTemplate(String id) async {
    await _apiClient.dio.delete<void>('/api/report-templates/$id');
  }

  Future<ReportTemplate> setDefaultTemplate(String id) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/report-templates/$id/default',
    );

    final data = _extractData(response.data);
    return ReportTemplate.fromMap(data['template'] as Map<String, dynamic>);
  }

  Map<String, dynamic> _extractData(Map<String, dynamic>? raw) {
    if (raw == null) return {};
    final data = raw['data'];
    if (data is Map<String, dynamic>) return data;
    return raw;
  }
}
