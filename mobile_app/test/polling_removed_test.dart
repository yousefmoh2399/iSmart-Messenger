import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile has no API/data polling timers', () {
    final root = Directory('lib');
    final offenders = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      final source = utf8.decode(
        entity.readAsBytesSync(),
        allowMalformed: true,
      );

      if (source.contains('BackgroundPollingManager') ||
          source.contains('backgroundPollingManagerProvider') ||
          source.contains('healthTimer') ||
          source.contains('heartbeatTimer') ||
          source.contains('Timer.periodic')) {
        if (path.endsWith(
              'features/chat/presentation/conversation_screen.dart',
            ) &&
            source.contains('_recordingTicker')) {
          continue;
        }
        offenders.add(path);
      }
    }

    expect(offenders, isEmpty);
  });
}
