import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../data/printer_repository.dart';
import '../models/printer_models.dart';

class MobilePrinterController extends AsyncNotifier<MobilePrinterOverview> {
  void resetState() { state = const AsyncLoading(); }

  MobilePrinterRepository get _repository =>
      ref.read(mobilePrinterRepositoryProvider);

  bool _canViewPrinters({bool listen = false}) {
    final user = listen
        ? ref.watch(currentUserProvider)
        : ref.read(currentUserProvider);
    return user?.canViewPrinterModule == true;
  }

  @override
  Future<MobilePrinterOverview> build() {
    ref.watch(serverRecoveryRevisionProvider);
    if (!_canViewPrinters(listen: true)) {
      return Future.value(MobilePrinterOverview.empty);
    }
    return _repository.fetchOverview();
  }

  Future<void> refresh() async {
    if (!_canViewPrinters()) {
      state = const AsyncData(MobilePrinterOverview.empty);
      return;
    }
    state = await AsyncValue.guard(_repository.fetchOverview);
  }

  Future<void> fullSync() async {
    if (!_canViewPrinters()) return;
    await _repository.fullSync();
    await refresh();
  }
}





