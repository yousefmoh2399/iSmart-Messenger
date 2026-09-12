import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:socket_io_client/src/manager.dart' as socket_io_manager;
import 'package:desktop_app/features/chat/data/chat_socket_service.dart';

class FakeManager implements socket_io_manager.Manager {
  @override
  dynamic Function() on(String event, dynamic Function(dynamic) fn) {
    return () => null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeSocket implements socket_io.Socket {
  final Map<String, List<dynamic Function(dynamic)>> listeners = {};
  int offCallCount = 0;
  int onCallCount = 0;
  bool _connected = false;

  @override
  socket_io_manager.Manager get io => FakeManager();

  @override
  bool get connected => _connected;

  @override
  socket_io.Socket connect() {
    _connected = true;
    return this;
  }

  @override
  socket_io.Socket disconnect() {
    _connected = false;
    return this;
  }

  @override
  socket_io.Socket dispose() {
    _connected = false;
    return this;
  }

  @override
  dynamic Function() on(String event, dynamic Function(dynamic) fn) {
    onCallCount++;
    listeners.putIfAbsent(event, () => []).add(fn);
    return () => off(event, fn);
  }

  @override
  void off(String event, [dynamic fn]) {
    offCallCount++;
    if (fn == null) {
      listeners.remove(event);
    } else {
      final list = listeners[event];
      if (list != null) {
        list.remove(fn);
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

void main() {
  group('ChatSocketService Listener Tests', () {
    test('Repeated initialization registers handler exactly once', () async {
      final service = ChatSocketService();
      final socket = FakeSocket();

      // Connect 4 times
      for (var i = 0; i < 4; i++) {
        await service.connect(
          baseUrl: 'http://localhost',
          token: 'token-$i',
          socketOverride: socket,
        );
      }

      // Check how many print_job_requested handlers are active on the socket
      final printHandlers = socket.listeners['print_job_requested'] ?? [];
      expect(printHandlers.length, equals(1));
    });

    test('Reconnect callbacks register handler exactly once', () async {
      // Re-triggering connect/bind multiple times maintains exactly one listener
      final service = ChatSocketService();
      final socket = FakeSocket();

      await service.connect(
        baseUrl: 'http://localhost',
        token: 'token',
        socketOverride: socket,
      );

      // Simulate multiple reconnection binds
      await service.connect(
        baseUrl: 'http://localhost',
        token: 'token',
        socketOverride: socket,
      );
      await service.connect(
        baseUrl: 'http://localhost',
        token: 'token',
        socketOverride: socket,
      );

      final printHandlers = socket.listeners['print_job_requested'] ?? [];
      expect(printHandlers.length, equals(1));
    });

    test('Unrelated listener is preserved when service binds', () async {
      final service = ChatSocketService();
      final socket = FakeSocket();

      // Register an unrelated listener first
      void unrelatedHandler(dynamic data) {}
      socket.on('print_job_requested', unrelatedHandler);

      // Connect service to the same socket, forcing a bind
      await service.connect(
        baseUrl: 'http://localhost',
        token: 'token',
        socketOverride: socket,
      );

      final printHandlers = socket.listeners['print_job_requested'] ?? [];
      
      // Expected: 1 service handler + 1 unrelated handler = 2 handlers
      expect(printHandlers.length, equals(2));
      expect(printHandlers.contains(unrelatedHandler), isTrue);

      // Trigger another connect (bind) to ensure unrelated is still preserved
      await service.connect(
        baseUrl: 'http://localhost',
        token: 'token',
        socketOverride: socket,
      );

      final printHandlersAfter = socket.listeners['print_job_requested'] ?? [];
      expect(printHandlersAfter.length, equals(2));
      expect(printHandlersAfter.contains(unrelatedHandler), isTrue);
    });

    test('Switching Socket instances removes handlers from old socket and registers on new socket', () async {
      final service = ChatSocketService();
      final socketA = FakeSocket();
      final socketB = FakeSocket();

      // Connect to socketA
      await service.connect(
        baseUrl: 'http://localhost',
        token: 'token',
        socketOverride: socketA,
      );

      expect(socketA.listeners['print_job_requested']?.length, equals(1));
      expect(socketB.listeners['print_job_requested']?.length, isNull);

      // Connect to socketB (causing disconnect/switch)
      await service.connect(
        baseUrl: 'http://localhost2',
        token: 'token2',
        socketOverride: socketB,
      );

      // Handlers on socketA should be cleaned up
      expect(socketA.listeners['print_job_requested']?.length, equals(0));
      // Handlers on socketB should be registered exactly once
      expect(socketB.listeners['print_job_requested']?.length, equals(1));
    });

    test('Dispose cleans up service handlers but preserves unrelated external ones', () async {
      final service = ChatSocketService();
      final socket = FakeSocket();

      // Register unrelated handler
      void unrelatedHandler(dynamic data) {}
      socket.on('print_job_requested', unrelatedHandler);

      // Connect service
      await service.connect(
        baseUrl: 'http://localhost',
        token: 'token',
        socketOverride: socket,
      );

      expect(socket.listeners['print_job_requested']?.length, equals(2));

      // Dispose service
      service.dispose();

      // Unrelated listener must remain, but service listener must be removed
      final remaining = socket.listeners['print_job_requested'] ?? [];
      expect(remaining.length, equals(1));
      expect(remaining.contains(unrelatedHandler), isTrue);
    });
  });
}
