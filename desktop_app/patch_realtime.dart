import 'dart:io';

void main() {
  var file = File('lib/features/chat/presentation/chat_realtime_controller.dart');
  var code = file.readAsStringSync();

  var insertPoint = code.indexOf('String _ticketNotificationFallbackTitle');
  if (insertPoint == -1) insertPoint = code.length;

  var reconnectCode = '''
  void reconnect() {
    state = ChatRealtimeState(
      status: ChatConnectionStatus.connecting,
      message: 'جاري إعادة الاتصال...',
      lastChangedAt: DateTime.now(),
    );
    ref.invalidate(chatSocketConnectionProvider);
  }

''';

  code = code.substring(0, insertPoint) + reconnectCode + code.substring(insertPoint);
  file.writeAsStringSync(code);
}
