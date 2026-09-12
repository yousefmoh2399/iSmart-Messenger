import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/settings/user_preferences_store.dart';
import 'local_media_storage_service.dart';

class AppErrorLogService {
  AppErrorLogService._();

  static final AppErrorLogService instance = AppErrorLogService._();

  final UserPreferencesStore _preferencesStore = UserPreferencesStore();
  final LocalMediaStorageService _storageService =
      const LocalMediaStorageService();

  Future<void> _lastWrite = Future<void>.value();

  Future<void> record(
    Object error, {
    StackTrace? stackTrace,
    String source = 'app',
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    _lastWrite = _lastWrite.then(
      (_) => _write(
        error,
        stackTrace: stackTrace,
        source: source,
        context: context,
      ),
      onError: (_) => _write(
        error,
        stackTrace: stackTrace,
        source: source,
        context: context,
      ),
    );
    return _lastWrite;
  }

  Future<void> _write(
    Object error, {
    required StackTrace? stackTrace,
    required String source,
    required Map<String, Object?> context,
  }) async {
    try {
      final preferences = await _preferencesStore.load();
      final root = await _storageService.resolveRootDirectory(
        preferredPath: preferences.localStorageDirectoryPath,
      );
      final file = File(p.join(root.path, 'log error.txt'));
      final entry = _formatEntry(
        error,
        stackTrace: stackTrace,
        source: source,
        context: context,
      );
      await file.writeAsString(entry, mode: FileMode.append, flush: true);
    } catch (logError) {
      debugPrint('Failed to write app error log: $logError');
    }
  }

  Future<void> recordDioException(DioException error, {String source = 'api'}) {
    final request = error.requestOptions;
    return record(
      error,
      stackTrace: error.stackTrace,
      source: source,
      context: <String, Object?>{
        'method': request.method,
        'path': request.path,
        'baseUrl': request.baseUrl,
        'statusCode': error.response?.statusCode,
        'type': error.type.name,
        'message': error.message,
        'response': _truncate(error.response?.data),
      },
    );
  }

  String _formatEntry(
    Object error, {
    required StackTrace? stackTrace,
    required String source,
    required Map<String, Object?> context,
  }) {
    final buffer = StringBuffer()
      ..writeln('============================================================')
      ..writeln('time: ${DateTime.now().toIso8601String()}')
      ..writeln('source: $source')
      ..writeln('error: $error');

    if (context.isNotEmpty) {
      buffer.writeln('context:');
      for (final entry in context.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    if (stackTrace != null) {
      buffer
        ..writeln('stackTrace:')
        ..writeln(stackTrace);
    }
    buffer.writeln();
    return buffer.toString();
  }

  Object? _truncate(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString();
    if (text.length <= 2000) {
      return text;
    }
    return '${text.substring(0, 2000)}... [truncated]';
  }
}
