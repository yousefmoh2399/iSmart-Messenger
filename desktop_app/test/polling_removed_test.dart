import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop has no API/data polling timers', () {
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
        if (path.endsWith('shared/services/web_platform_bridge_web.dart') &&
            source.contains('_titleAttentionTimer')) {
          continue;
        }
        offenders.add(path);
      }
    }

    expect(offenders, isEmpty);
  });
}
