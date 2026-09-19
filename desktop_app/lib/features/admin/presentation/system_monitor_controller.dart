import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/providers.dart';
import '../models/system_monitor_models.dart';

class SystemMonitorState {
  const SystemMonitorState({
    this.sessions = const [],
    this.errors = const [],
    this.isLoadingSessions = false,
    this.isLoadingErrors = false,
    this.sessionsPage = 1,
    this.sessionsHasMore = false,
    this.errorsPage = 1,
    this.errorsHasMore = false,
    this.sessionsTotal = 0,
    this.errorsTotal = 0,
    this.statusFilter = 'all',
    this.clientTypeFilter = 'all',
    this.searchQuery = '',
    this.selectedUserId,
    this.selectedSessionId,
    this.resolvedFilter,
  });

  final List<DeviceSession> sessions;
  final List<ClientErrorLog> errors;
  final bool isLoadingSessions;
  final bool isLoadingErrors;
  final int sessionsPage;
  final bool sessionsHasMore;
  final int errorsPage;
  final bool errorsHasMore;
  final int sessionsTotal;
  final int errorsTotal;
  
  final String statusFilter;
  final String clientTypeFilter;
  final String searchQuery;

  final String? selectedUserId;
  final String? selectedSessionId;
  final bool? resolvedFilter;

  SystemMonitorState copyWith({
    List<DeviceSession>? sessions,
    List<ClientErrorLog>? errors,
    bool? isLoadingSessions,
    bool? isLoadingErrors,
    int? sessionsPage,
    bool? sessionsHasMore,
    int? errorsPage,
    bool? errorsHasMore,
    int? sessionsTotal,
    int? errorsTotal,
    String? statusFilter,
    String? clientTypeFilter,
    String? searchQuery,
    String? selectedUserId,
    String? selectedSessionId,
    bool? resolvedFilter,
  }) {
    return SystemMonitorState(
      sessions: sessions ?? this.sessions,
      errors: errors ?? this.errors,
      isLoadingSessions: isLoadingSessions ?? this.isLoadingSessions,
      isLoadingErrors: isLoadingErrors ?? this.isLoadingErrors,
      sessionsPage: sessionsPage ?? this.sessionsPage,
      sessionsHasMore: sessionsHasMore ?? this.sessionsHasMore,
      errorsPage: errorsPage ?? this.errorsPage,
      errorsHasMore: errorsHasMore ?? this.errorsHasMore,
      sessionsTotal: sessionsTotal ?? this.sessionsTotal,
      errorsTotal: errorsTotal ?? this.errorsTotal,
      statusFilter: statusFilter ?? this.statusFilter,
      clientTypeFilter: clientTypeFilter ?? this.clientTypeFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedUserId: selectedUserId != null ? (selectedUserId == '' ? null : selectedUserId) : this.selectedUserId,
      selectedSessionId: selectedSessionId != null ? (selectedSessionId == '' ? null : selectedSessionId) : this.selectedSessionId,
      resolvedFilter: resolvedFilter != null ? (resolvedFilter == true ? true : (resolvedFilter == false ? false : null)) : this.resolvedFilter,
    );
  }
}

class SystemMonitorController extends Notifier<SystemMonitorState> {
  @override
  SystemMonitorState build() {
    Future.microtask(() => refreshSessions());
    return const SystemMonitorState();
  }

  Future<void> refreshSessions() async {
    state = state.copyWith(isLoadingSessions: true, sessionsPage: 1);
    try {
      final repo = ref.read(systemMonitorRepositoryProvider);
      final res = await repo.getConnections(
        page: 1,
        status: state.statusFilter,
        clientType: state.clientTypeFilter,
        search: state.searchQuery,
      );
      state = state.copyWith(
        sessions: res.items,
        sessionsPage: res.page,
        sessionsHasMore: res.hasMore,
        sessionsTotal: res.total,
        isLoadingSessions: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingSessions: false);
    }
  }

  Future<void> loadMoreSessions() async {
    if (state.isLoadingSessions || !state.sessionsHasMore) return;
    state = state.copyWith(isLoadingSessions: true);
    try {
      final repo = ref.read(systemMonitorRepositoryProvider);
      final res = await repo.getConnections(
        page: state.sessionsPage + 1,
        status: state.statusFilter,
        clientType: state.clientTypeFilter,
        search: state.searchQuery,
      );
      state = state.copyWith(
        sessions: [...state.sessions, ...res.items],
        sessionsPage: res.page,
        sessionsHasMore: res.hasMore,
        sessionsTotal: res.total,
        isLoadingSessions: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingSessions: false);
    }
  }

  void setFilters({String? status, String? clientType, String? search}) {
    state = state.copyWith(
      statusFilter: status,
      clientTypeFilter: clientType,
      searchQuery: search,
    );
    refreshSessions();
  }

  Future<void> loadErrors({String? userId, String? sessionId, bool? resolved}) async {
    state = state.copyWith(
      isLoadingErrors: true, 
      errorsPage: 1,
      selectedUserId: userId ?? '',
      selectedSessionId: sessionId ?? '',
      resolvedFilter: resolved,
    );
    try {
      final repo = ref.read(systemMonitorRepositoryProvider);
      final res = await repo.getErrors(
        page: 1,
        userId: userId,
        sessionId: sessionId,
        resolved: resolved,
      );
      state = state.copyWith(
        errors: res.items,
        errorsPage: res.page,
        errorsHasMore: res.hasMore,
        errorsTotal: res.total,
        isLoadingErrors: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingErrors: false);
    }
  }

  Future<void> loadMoreErrors() async {
    if (state.isLoadingErrors || !state.errorsHasMore) return;
    state = state.copyWith(isLoadingErrors: true);
    try {
      final repo = ref.read(systemMonitorRepositoryProvider);
      final res = await repo.getErrors(
        page: state.errorsPage + 1,
        userId: state.selectedUserId,
        sessionId: state.selectedSessionId,
        resolved: state.resolvedFilter,
      );
      state = state.copyWith(
        errors: [...state.errors, ...res.items],
        errorsPage: res.page,
        errorsHasMore: res.hasMore,
        errorsTotal: res.total,
        isLoadingErrors: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingErrors: false);
    }
  }

  Future<void> resolveError(String id) async {
    try {
      final repo = ref.read(systemMonitorRepositoryProvider);
      final updated = await repo.resolveError(id);
      state = state.copyWith(
        errors: state.errors.map((e) => e.id == id ? updated : e).toList(),
      );
    } catch (_) {}
  }

  Future<void> deleteAllErrors() async {
    try {
      final repo = ref.read(systemMonitorRepositoryProvider);
      await repo.deleteAllErrors();
      state = state.copyWith(errors: []);
    } catch (_) {}
  }
}

final systemMonitorControllerProvider =
    NotifierProvider<SystemMonitorController, SystemMonitorState>(
  SystemMonitorController.new,
);
