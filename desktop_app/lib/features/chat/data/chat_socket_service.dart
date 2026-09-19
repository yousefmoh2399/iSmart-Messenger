import 'dart:async';
import 'dart:io' as io_dart;

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../../shared/services/print_job_processor.dart';

class ChatSocketEvent {
  const ChatSocketEvent({required this.type, required this.payload});

  final String type;
  final Map<String, dynamic> payload;
}

class ChatSocketService implements PrintStatusEmitter {
  final StreamController<ChatSocketEvent> _eventsController =
      StreamController<ChatSocketEvent>.broadcast();
  final Set<String> _joinedConversationIds = <String>{};

  io.Socket? _socket;
  String? _connectedBaseUrl;
  String? _connectedToken;
  String _presenceStatus = 'online';
  bool _manualDisconnect = false;
  final Map<String, dynamic Function(dynamic)> _exactHandlers =
      <String, dynamic Function(dynamic)>{};

  Stream<ChatSocketEvent> get events => _eventsController.stream;

  bool get isConnected => _socket?.connected == true;

  String? get socketId => _socket?.id;

  bool _isSessionExpiredError(Object? error) {
    final message = error?.toString().toLowerCase() ?? '';
    return message.contains('session expired') ||
        message.contains('login again') ||
        message.contains('invalid or expired token') ||
        message.contains('token version mismatch');
  }

  Future<void> connect({
    required String baseUrl,
    required String token,
    String clientType = 'desktop',
    io.Socket? socketOverride,
  }) async {
    if (isConnected &&
        _connectedBaseUrl == baseUrl &&
        _connectedToken == token) {
      return;
    }

    disconnect();
    _connectedBaseUrl = baseUrl;
    _connectedToken = token;
    _presenceStatus = 'online';
    _manualDisconnect = false;

    final completer = Completer<void>();
    Map<String, dynamic> deviceInfo = {};
    if (!const bool.fromEnvironment('dart.library.html')) {
      try {
        deviceInfo = {
          'os': io_dart.Platform.operatingSystem,
          'osVersion': io_dart.Platform.operatingSystemVersion,
          'hostname': io_dart.Platform.localHostname,
        };
      } catch (_) {}
    }

    final socket =
        socketOverride ??
        io.io(
          baseUrl,
          io.OptionBuilder()
              .setTransports(['websocket'])
              .setPath('/socket.io')
              .enableForceNew()
              .disableAutoConnect()
              .enableReconnection()
              .setReconnectionDelay(1200)
              .setReconnectionDelayMax(4000)
              .setAuth({
                'token': token, 
                'clientType': clientType,
                'deviceInfo': deviceInfo,
              })
              .setExtraHeaders({
                'Authorization': 'Bearer $token',
                'x-client-type': clientType,
              })
              .build(),
        );

    void stopRejectedSocket() {
      _manualDisconnect = true;
      try {
        socket.disconnect();
        socket.dispose();
      } catch (_) {}
      if (identical(_socket, socket)) {
        _socket = null;
        _connectedBaseUrl = null;
        _connectedToken = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    socket.onConnect((_) {
      _manualDisconnect = false;
      _rejoinConversations();
      _emitPresenceStatus(_presenceStatus);
      _eventsController.add(
        const ChatSocketEvent(type: 'socket_connected', payload: {}),
      );
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    if (socketOverride != null) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    socket.onReconnect((_) {
      _manualDisconnect = false;
      _rejoinConversations();
      _eventsController.add(
        const ChatSocketEvent(type: 'socket_connected', payload: {}),
      );
    });
    socket.onConnectError((error) {
      if (_isSessionExpiredError(error)) {
        _eventsController.add(
          ChatSocketEvent(
            type: 'session_expired',
            payload: {
              'message':
                  error?.toString() ?? 'Session expired. Please login again.',
            },
          ),
        );
        stopRejectedSocket();
        return;
      }
      if (!completer.isCompleted) {
        _eventsController.add(
          ChatSocketEvent(
            type: 'socket_reconnecting',
            payload: {
              'message': error?.toString() ?? 'Socket connection failed',
            },
          ),
        );
        Future.delayed(const Duration(seconds: 4), () {
          if (!_manualDisconnect && socket.disconnected) {
            socket.connect();
          }
        });
        return;
      }
      _eventsController.add(
        ChatSocketEvent(
          type: 'socket_reconnecting',
          payload: {'message': error?.toString() ?? 'Socket connection failed'},
        ),
      );
    });
    socket.onReconnectAttempt((attempt) {
      _eventsController.add(
        ChatSocketEvent(
          type: 'socket_reconnecting',
          payload: {'attempt': attempt},
        ),
      );
    });
    socket.onReconnectError((error) {
      if (_isSessionExpiredError(error)) {
        _eventsController.add(
          ChatSocketEvent(
            type: 'session_expired',
            payload: {
              'message':
                  error?.toString() ?? 'Session expired. Please login again.',
            },
          ),
        );
        stopRejectedSocket();
        return;
      }
      _eventsController.add(
        ChatSocketEvent(
          type: 'socket_reconnecting',
          payload: {'message': error?.toString() ?? 'Socket reconnect failed'},
        ),
      );
    });
    socket.onReconnectFailed((_) {
      _eventsController.add(
        const ChatSocketEvent(type: 'socket_disconnected', payload: {}),
      );
    });
    socket.onError((error) {
      if (_isSessionExpiredError(error)) {
        _eventsController.add(
          ChatSocketEvent(
            type: 'session_expired',
            payload: {
              'message':
                  error?.toString() ?? 'Session expired. Please login again.',
            },
          ),
        );
        stopRejectedSocket();
        return;
      }
      _eventsController.add(
        ChatSocketEvent(
          type: 'socket_error',
          payload: {'message': error?.toString() ?? 'Socket error'},
        ),
      );
    });
    socket.onDisconnect((reason) {
      if (_manualDisconnect) {
        return;
      }
      _eventsController.add(
        ChatSocketEvent(
          type: 'socket_reconnecting',
          payload: {'reason': reason},
        ),
      );
    });

    void bind(String eventName) {
      final oldHandler = _exactHandlers[eventName];
      if (oldHandler != null && _socket != null) {
        _socket!.off(eventName, oldHandler);
      }
      void newHandler(dynamic data) {
        final normalizedData = data is List && data.isNotEmpty
            ? data.first
            : data;
        final payload = normalizedData is Map
            ? Map<String, dynamic>.from(normalizedData)
            : <String, dynamic>{'value': normalizedData};
        _eventsController.add(
          ChatSocketEvent(type: eventName, payload: payload),
        );
      }

      _exactHandlers[eventName] = newHandler;
      socket.on(eventName, newHandler);
    }

    bind('receive_message');
    bind('typing');
    bind('stop_typing');
    bind('message_seen');
    bind('message_delivered');
    bind('conversation_updated');
    bind('unread_count_updated');
    bind('message_deleted');
    bind('message_updated');
    bind('message_reaction_added');
    bind('conversation_deleted');
    bind('conversation_state_changed');
    bind('user_online');
    bind('user_offline');
    bind('presence_updated');
    bind('announcements_updated');
    bind('app_settings_updated');
    bind('updates_updated');
    bind('departments_updated');
    bind('branches_updated');
    bind('users_updated');
    bind('user_profile_updated');
    bind('force_logout');
    bind('printers_catalog_updated');
    bind('printers_catalog_refresh_requested');
    bind('print_job_status');
    bind('print_job_requested');
    bind('desktop_storage_updated');
    bind('file_save_requested');
    bind('file_save_progress');
    bind('file_save_status');
    bind('file_receive_requested');
    bind('file_receive_progress');
    bind('file_receive_status');
    bind('attachment_rehydrate_requested');
    bind('ticket_updated');
    bind('tickets_updated');
    bind('ticket_settings_updated');

    socket.connect();
    _socket = socket;
    try {
      await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      _eventsController.add(
        const ChatSocketEvent(type: 'socket_reconnecting', payload: {}),
      );
      return;
    } catch (e, stackTrace) {
      try {
        socket.disconnect();
        socket.dispose();
      } catch (_) {}
      _socket = null;
      _connectedBaseUrl = null;
      _connectedToken = null;
      Error.throwWithStackTrace(e, stackTrace);
    }
  }

  void joinConversation(String conversationId) {
    _joinedConversationIds.add(conversationId);
    setPresenceOnline();
    _socket?.emit('join_conversation', {'conversationId': conversationId});
  }

  void leaveConversation(String conversationId) {
    _joinedConversationIds.remove(conversationId);
    _socket?.emit('leave_conversation', {'conversationId': conversationId});
  }

  void sendTyping(String conversationId) {
    setPresenceOnline();
    _socket?.emit('typing', {'conversationId': conversationId});
  }

  void stopTyping(String conversationId) {
    _socket?.emit('stop_typing', {'conversationId': conversationId});
  }

  void markSeen(String conversationId) {
    setPresenceOnline();
    _socket?.emit('message_seen', {'conversationId': conversationId});
  }

  void markActivity() {
    setPresenceOnline();
  }

  void setPresenceOnline() {
    setPresenceStatus('online');
  }

  void setPresenceIdle() {
    setPresenceStatus('idle');
  }

  void setPresenceMeeting() {
    setPresenceStatus('meeting');
  }

  void setPresenceLunch() {
    setPresenceStatus('lunch');
  }

  void setPresenceOffline() {
    setPresenceStatus('offline', forceEmit: true);
  }

  void setPresenceStatus(String status, {bool forceEmit = false}) {
    final normalized = switch (status.toLowerCase()) {
      'online' => 'online',
      'idle' => 'idle',
      'meeting' => 'meeting',
      'lunch' => 'lunch',
      'offline' => 'offline',
      _ => 'online',
    };
    if (!forceEmit && _presenceStatus == normalized && isConnected) {
      return;
    }
    _presenceStatus = normalized;
    _emitPresenceStatus(normalized);
  }

  void _emitPresenceStatus(String status) {
    _socket?.emit('presence:activity', {'status': status});
  }

  @override
  void emitEvent(String eventName, [Map<String, dynamic> payload = const {}]) {
    _socket?.emit(eventName, payload);
  }

  Future<Map<String, dynamic>> emitWithAck(
    String eventName,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final socket = await _waitForConnectedSocket(timeout: timeout);
    if (socket == null) {
      return <String, dynamic>{
        'ok': false,
        'success': false,
        'error': 'Socket is not connected.',
      };
    }

    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(
      eventName,
      payload,
      ack: (dynamic data) {
        final map = data is Map
            ? Map<String, dynamic>.from(data)
            : <String, dynamic>{
                'ok': false,
                'success': false,
                'error': 'Unexpected ack payload',
              };
        if (!completer.isCompleted) {
          completer.complete(map);
        }
      },
    );

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return <String, dynamic>{
        'ok': false,
        'success': false,
        'error': 'Socket ack timeout.',
      };
    }
  }

  Future<io.Socket?> _waitForConnectedSocket({
    required Duration timeout,
  }) async {
    final socket = _socket;
    if (socket == null) {
      return null;
    }
    if (socket.connected) {
      return socket;
    }

    final waitTimeout = timeout < const Duration(seconds: 6)
        ? timeout
        : const Duration(seconds: 6);
    try {
      await events
          .firstWhere((event) => event.type == 'socket_connected')
          .timeout(waitTimeout);
    } catch (_) {}

    final latest = _socket;
    return latest != null && latest.connected ? latest : null;
  }

  void _rejoinConversations() {
    for (final conversationId in _joinedConversationIds) {
      _socket?.emit('join_conversation', {'conversationId': conversationId});
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _presenceStatus = 'offline';
    final socket = _socket;
    if (socket == null) {
      _connectedBaseUrl = null;
      _connectedToken = null;
      _joinedConversationIds.clear();
      _exactHandlers.clear();
      return;
    }

    if (socket.connected) {
      socket.emit('presence:activity', {'status': 'offline'});
    }

    for (final entry in _exactHandlers.entries) {
      try {
        socket.off(entry.key, entry.value);
      } catch (_) {}
    }
    _exactHandlers.clear();

    socket.disconnect();
    socket.dispose();

    _socket = null;
    _connectedBaseUrl = null;
    _connectedToken = null;
    _joinedConversationIds.clear();
  }

  void reportClientError({
    required String source,
    required String errorMessage,
    Map<String, dynamic>? errorContext,
    String? stackTrace,
  }) {
    if (!isConnected) return;
    _socket?.emitWithAck(
      'report_client_error',
      {
        'source': source,
        'errorMessage': errorMessage,
        'errorContext': errorContext,
        'stackTrace': stackTrace,
      },
      ack: (_) {},
    );
  }

  void dispose() {
    disconnect();
    _eventsController.close();
  }
}
