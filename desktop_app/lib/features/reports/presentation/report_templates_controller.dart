import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/report_template_repository.dart';
import '../models/report_template_models.dart';

final reportTemplatesFamilyProvider = FutureProvider.family<List<ReportTemplate>, String>((ref, reportType) async {
  final repository = ref.watch(reportTemplateRepositoryProvider);
  return repository.fetchTemplates(reportType);
});

final availableColumnsFamilyProvider = FutureProvider.family<List<ReportColumn>, String>((ref, reportType) async {
  final repository = ref.watch(reportTemplateRepositoryProvider);
  return repository.fetchAvailableColumns(reportType);
});

final reportTemplatesProvider = reportTemplatesFamilyProvider;
final availableColumnsProvider = availableColumnsFamilyProvider;

final reportTemplateActionControllerProvider = StateNotifierProvider<ReportTemplateActionNotifier, AsyncValue<void>>((ref) {
  final repository = ref.watch(reportTemplateRepositoryProvider);
  return ReportTemplateActionNotifier(repository, ref);
});

class ReportTemplateActionNotifier extends StateNotifier<AsyncValue<void>> {
  ReportTemplateActionNotifier(this._repository, this._ref)
      : super(const AsyncValue.data(null));

  final ReportTemplateRepository _repository;
  final Ref _ref;

  Future<ReportTemplate?> saveTemplate(ReportTemplate template) async {
    state = const AsyncValue.loading();
    try {
      ReportTemplate result;
      if (template.id.isNotEmpty) {
        result = await _repository.updateTemplate(template.id, template);
      } else {
        result = await _repository.createTemplate(template);
      }
      _ref.invalidate(reportTemplatesFamilyProvider(template.reportType));
      state = const AsyncValue.data(null);
      return result;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> deleteTemplate(String id, String reportType) async {
    state = const AsyncValue.loading();
    try {
      await _repository.deleteTemplate(id);
      _ref.invalidate(reportTemplatesFamilyProvider(reportType));
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> setDefault(String id, String reportType) async {
    state = const AsyncValue.loading();
    try {
      await _repository.setDefaultTemplate(id);
      _ref.invalidate(reportTemplatesFamilyProvider(reportType));
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }
}
