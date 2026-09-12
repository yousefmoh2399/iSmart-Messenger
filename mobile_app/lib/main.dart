import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/mobile_app.dart';
import 'shared/services/app_error_log_service.dart';
import 'shared/services/push_notification_service.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final defaultFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        unawaited(
          AppErrorLogService.instance.record(
            details.exception,
            stackTrace: details.stack,
            source: 'flutter',
            context: <String, Object?>{
              'library': details.library,
              'context': details.context?.toDescription(),
            },
          ),
        );
        defaultFlutterErrorHandler?.call(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        if (error is MissingPluginException) {
          final msg = error.message ?? '';
          if (msg.contains('disposeAllPlayers')) {
            return true;
          }
        }
        unawaited(
          AppErrorLogService.instance.record(
            error,
            stackTrace: stack,
            source: 'platform_dispatcher',
          ),
        );
        return false;
      };
      await PushNotificationService.registerBackgroundHandler();
      runApp(const ProviderScope(child: WorkplaceMobileApp()));
    },
    (error, stack) {
      if (error is MissingPluginException) {
        final msg = error.message ?? '';
        if (msg.contains('disposeAllPlayers')) {
          return;
        }
      }
      unawaited(
        AppErrorLogService.instance.record(
          error,
          stackTrace: stack,
          source: 'zone',
        ),
      );
    },
  );
}
