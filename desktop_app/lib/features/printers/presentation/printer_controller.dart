import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../data/printer_repository.dart';
import '../models/printer_models.dart';

class PrinterController extends AsyncNotifier<PrinterOverviewData> {
  PrinterRepository get _repository => ref.read(printerRepositoryProvider);

  bool _canViewPrinters({bool listen = false}) {
    final user = listen
        ? ref.watch(currentUserProvider)
        : ref.read(currentUserProvider);
    return user?.canViewPrinterModule == true;
  }

  @override
  Future<PrinterOverviewData> build() {
    ref.watch(serverRecoveryRevisionProvider);
    if (!_canViewPrinters(listen: true)) {
      return Future.value(PrinterOverviewData.empty);
    }
    return _repository.fetchOverview();
  }

  Future<void> refresh() async {
    if (!_canViewPrinters()) {
      state = const AsyncData(PrinterOverviewData.empty);
      return;
    }
    final previous = state.valueOrNull;
    final next = await AsyncValue.guard(_repository.fetchOverview);
    if (next.hasError && previous != null) {
      state = AsyncData(previous.copyWith(isOffline: true));
      return;
    }
    state = next;
  }

  Future<void> createBranch({
    required String name,
    required String code,
    required String networkRange,
    required String location,
  }) async {
    if (!_canViewPrinters()) return;
    await _repository.createBranch(
      name: name,
      code: code,
      networkRange: networkRange,
      location: location,
    );
    await refresh();
  }

  Future<void> updateBranch({
    required String branchId,
    required String name,
    required String code,
    required String networkRange,
    required String location,
    required String status,
  }) async {
    if (!_canViewPrinters()) return;
    await _repository.updateBranch(
      branchId: branchId,
      name: name,
      code: code,
      networkRange: networkRange,
      location: location,
      status: status,
    );
    await refresh();
  }

  Future<void> deleteBranch(String branchId) async {
    if (!_canViewPrinters()) return;
    await _repository.deleteBranch(branchId);
    await refresh();
  }

  Future<void> discoverBranch(String branchId) async {
    if (!_canViewPrinters()) return;
    await _repository.discoverBranch(branchId);
    await refresh();
  }

  Future<void> fullSync() async {
    if (!_canViewPrinters()) return;
    await _repository.fullSync();
    await refresh();
  }

  Future<void> stopFullSync() async {
    if (!_canViewPrinters()) return;
    await _repository.stopFullSync();
    await refresh();
  }

  Future<Map<String, dynamic>> fetchFullSyncStatus() {
    if (!_canViewPrinters()) return Future.value(<String, dynamic>{});
    return _repository.fetchFullSyncStatus();
  }

  Future<void> syncPrinter(String printerId) async {
    if (!_canViewPrinters()) return;
    await _repository.syncPrinter(printerId);
    await refresh();
  }

  Future<void> deletePrinter(String printerId) async {
    if (!_canViewPrinters()) return;
    await _repository.deletePrinter(printerId);
    await refresh();
  }

  Future<void> exportReport({
    required String format,
    String? type,
    String? branchId,
    int? fromMonth,
    int? fromYear,
    int? toMonth,
    int? toYear,
  }) {
    if (!_canViewPrinters()) return Future<void>.value();
    return _repository.exportReport(
      format: format,
      type: type,
      branchId: branchId,
      fromMonth: fromMonth,
      fromYear: fromYear,
      toMonth: toMonth,
      toYear: toYear,
    );
  }

  Future<void> exportMonthlyReport({
    required String format,
    String? type,
    String? branchId,
    int? fromMonth,
    int? fromYear,
    int? toMonth,
    int? toYear,
  }) {
    if (!_canViewPrinters()) return Future<void>.value();
    return _repository.exportReport(
      format: format,
      type: type,
      branchId: branchId,
      fromMonth: fromMonth,
      fromYear: fromYear,
      toMonth: toMonth,
      toYear: toYear,
    );
  }
}
