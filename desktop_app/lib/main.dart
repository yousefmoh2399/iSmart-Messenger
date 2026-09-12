import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/desktop_app.dart';
import 'shared/services/app_error_log_service.dart';
import 'shared/services/windows_storage_migration.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final defaultFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        if (_isDisposedEngineViewError(details.exception)) {
          return;
        }
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
        if (_isDisposedEngineViewError(error)) {
          return true;
        }
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
      await WindowsStorageMigration.migrateIfNeeded();
      runApp(const ProviderScope(child: WorkplaceDesktopApp()));
    },
    (error, stack) {
      if (_isDisposedEngineViewError(error)) {
        return;
      }
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

bool _isDisposedEngineViewError(Object error) {
  return kIsWeb && error.toString().contains('disposed EngineFlutterView');
}
