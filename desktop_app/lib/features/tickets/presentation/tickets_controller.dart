import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/providers.dart';
import '../../chat/data/chat_socket_service.dart';
import '../data/ticket_repository.dart';
import '../models/ticket_models.dart';

class TicketsController extends AsyncNotifier<TicketOverviewData> {
  StreamSubscription<ChatSocketEvent>? _eventsSubscription;
  TicketRepository? _repositoryInstance;

  TicketRepository _repository() =>
      _repositoryInstance ?? ref.read(ticketRepositoryProvider);

  @override
  Future<TicketOverviewData> build() async {
    ref.watch(serverRecoveryRevisionProvider);
    try {
      await ref.watch(chatSocketConnectionProvider.future);
    } catch (_) {
      // Keep tickets usable even when realtime socket fails temporarily.
    }
    _repositoryInstance = ref.read(ticketRepositoryProvider);
    _listenToSocket();
    ref.onDispose(() => _eventsSubscription?.cancel());
    return _repository().fetchOverview();
  }

  void _listenToSocket() {
    _eventsSubscription?.cancel();
    final socket = ref.read(chatSocketServiceProvider);
    _eventsSubscription = socket.events.listen((event) {
      if (event.type == 'ticket_updated' ||
          event.type == 'tickets_updated' ||
          event.type == 'ticket_settings_updated') {
        Future<void>.microtask(refresh);
      }
    });
  }

  Future<void> refresh({bool showLoader = false}) async {
    final previous = state.valueOrNull;
    if (showLoader || previous == null) {
      state = const AsyncLoading();
    }
    final next = await AsyncValue.guard(() => _repository().fetchOverview());
    if (next.hasError && previous != null) {
      state = AsyncData(previous);
      return;
    }
    state = next;
  }

  Future<TicketItem> createTicket({
    required String title,
    required String description,
    String priority = 'normal',
    String ticketType = 'ticket',
    String? targetDepartmentId,
  }) async {
    final ticket = await _repository().createTicket(
      title: title,
      description: description,
      priority: priority,
      ticketType: ticketType,
      targetDepartmentId: targetDepartmentId,
    );
    await refresh();
    return ticket;
  }

  Future<TicketSupportUsersData> fetchSupportUsers() {
    return _repository().fetchSupportUsers();
  }

  Future<void> updateSupportAgents(
    List<String> supportAgentIds, {
    Map exportPermissionsByUserId = const {},
  }) async {
    await _repository().updateSupportAgents(
      supportAgentIds,
      exportPermissionsByUserId: exportPermissionsByUserId,
    );
    await refresh();
  }

  Future<Map<String, List<Map<String, String>>>>
  fetchDepartmentHandlerAssignments({String handlerType = 'complaint'}) {
    return _repository().fetchDepartmentHandlerAssignments(
      handlerType: handlerType,
    );
  }

  Future<List<TicketActor>> fetchDepartmentHandlers(
    String departmentId, {
    String handlerType = 'complaint',
  }) {
    return _repository().fetchDepartmentHandlers(
      departmentId,
      handlerType: handlerType,
    );
  }

  Future<void> updateDepartmentHandlers(
    String departmentId,
    List<String> handlerIds, {
    String handlerType = 'complaint',
  }) async {
    await _repository().updateDepartmentHandlers(
      departmentId,
      handlerIds,
      handlerType: handlerType,
    );
  }

  Future<void> exportTicketsReport({
    String ticketType = 'ticket',
    String? status,
    String? priority,
    String? q,
    String format = 'xlsx',
  }) {
    return _repository().exportTicketsReport(
      ticketType: ticketType,
      status: status,
      priority: priority,
      q: q,
      format: format,
    );
  }
}

class TicketDetailsController
    extends AutoDisposeFamilyAsyncNotifier<TicketDetailsData, String> {
  StreamSubscription<ChatSocketEvent>? _eventsSubscription;
  TicketRepository? _repositoryInstance;
  bool _isRefreshing = false;

  TicketRepository _repository() =>
      _repositoryInstance ?? ref.read(ticketRepositoryProvider);

  @override
  Future<TicketDetailsData> build(String arg) async {
    ref.watch(serverRecoveryRevisionProvider);
    try {
      await ref.watch(chatSocketConnectionProvider.future);
    } catch (_) {
      // Keep ticket details usable even when realtime socket fails temporarily.
    }
    _repositoryInstance = ref.read(ticketRepositoryProvider);
    _listenToSocket(arg);
    ref.onDispose(() => _eventsSubscription?.cancel());
    return _repository().fetchTicketDetails(arg);
  }

  void _listenToSocket(String ticketId) {
    _eventsSubscription?.cancel();
    final socket = ref.read(chatSocketServiceProvider);
    _eventsSubscription = socket.events.listen((event) {
      if (event.type == 'ticket_updated' &&
          event.payload['ticketId']?.toString() == ticketId) {
        Future<void>.microtask(refresh);
        return;
      }
      if (event.type == 'tickets_updated' &&
          event.payload['ticketId']?.toString() == ticketId) {
        Future<void>.microtask(refresh);
      }
    });
  }

  Future<void> refresh() async {
    if (_isRefreshing) {
      return;
    }
    _isRefreshing = true;
    try {
      final data = await _repository().fetchTicketDetails(arg);
      state = AsyncData(data);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    } finally {
      _isRefreshing = false;
    }
  }

  Future<void> addComment(String message, {bool internalNote = false}) async {
    final current = state.valueOrNull;
    if (current == null) {
      await refresh();
      return;
    }
    final updated = await _repository().addComment(
      ticketId: current.ticket.id,
      message: message,
      internalNote: internalNote,
    );
    state = AsyncData(updated);
  }

  Future<void> updateStatus(String status) async {
    final current = state.valueOrNull;
    if (current == null) {
      await refresh();
      return;
    }
    final updated = await _repository().updateStatus(
      ticketId: current.ticket.id,
      status: status,
    );
    state = AsyncData(updated);
  }

  Future<void> assignTo(String? assignedToId) async {
    final current = state.valueOrNull;
    if (current == null) {
      await refresh();
      return;
    }

    try {
      final updated = await _repository().assignTicket(
        ticketId: current.ticket.id,
        assignedToId: assignedToId,
      );
      state = AsyncData(updated);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
      rethrow; // Re-throw to be handled by UI
    }
  }
}
