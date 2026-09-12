import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../features/auth/data/auth_session_manager.dart';
import '../../shared/services/app_error_log_service.dart';
import 'api_exception.dart';

class ApiClient {
  static Duration serverTimeOffset = Duration.zero;

  ApiClient({required String baseUrl, AuthSessionManager? sessionManager})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: kIsWeb ? null : const Duration(minutes: 10),
        ),
      ),
      _sessionManager = sessionManager {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (kIsWeb) {
            options.sendTimeout = null;
          }

          final requestPath = options.path.toLowerCase();
          options.extra['requiresAuth'] ??= !_isPublicAuthPath(requestPath);

          String? tokenFingerprint;
          if (_sessionManager != null &&
              options.extra['requiresAuth'] == true) {
            await _sessionManager.initialize();
            final token = _sessionManager.accessToken;
            final normalizedToken = token?.trim();
            final hasUsableToken =
                normalizedToken != null &&
                normalizedToken.isNotEmpty &&
                normalizedToken.toLowerCase() != 'null';

            if (hasUsableToken) {
              options.headers['Authorization'] = 'Bearer $normalizedToken';
              options.extra['accessTokenUsed'] = normalizedToken;
              options.extra['tokenGenerationUsed'] =
                  _sessionManager.tokenGeneration;
              tokenFingerprint =
                  '${normalizedToken.length}:${normalizedToken.substring(max(0, normalizedToken.length - 6))}';
            } else {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.cancel,
                  error: const MissingAuthTokenException(),
                ),
              );
              return;
            }
          }

          if (tokenFingerprint == null &&
              options.headers.containsKey('Authorization')) {
            final authHeader = options.headers['Authorization'] as String?;
            if (authHeader != null && authHeader.startsWith('Bearer ')) {
              final tokenVal = authHeader.substring(7).trim();
              if (tokenVal.isNotEmpty && tokenVal.toLowerCase() != 'null') {
                tokenFingerprint =
                    '${tokenVal.length}:${tokenVal.substring(max(0, tokenVal.length - 6))}';
              }
            }
          }

          final time = DateTime.now().toIso8601String();
          final source = options.extra['requestSource'] ?? 'unknown';
          final hasAuth = options.headers.containsKey('Authorization');
          final retryCount = (options.extra['authRetryCount'] as int?) ?? 0;
          final gen = options.extra['tokenGenerationUsed'] ?? 'null';

          debugPrint(
            '[API]\n'
            'time=$time\n'
            'source=$source\n'
            '${options.method} ${options.path}\n'
            'auth=$hasAuth\n'
            'token=$tokenFingerprint\n'
            'generation=$gen\n'
            'authRetryCount=$retryCount',
          );

          final isTransferEndpoint =
              requestPath.contains('/transfers') ||
              requestPath.contains('/upload') ||
              requestPath.contains('/download') ||
              requestPath.contains('/releases') ||
              requestPath.contains('/updates');
          if (!isTransferEndpoint) {
            options.receiveTimeout = const Duration(seconds: 90);
            if (!kIsWeb) {
              options.sendTimeout = const Duration(seconds: 90);
            }
          }

          handler.next(options);
        },
        onResponse: (response, handler) {
          _syncServerTime(response.headers.value('date'));
          handler.next(response);
        },
        onError: (error, handler) async {
          _syncServerTime(error.response?.headers.value('date'));

          final requestOptions = error.requestOptions;
          final statusCode = error.response?.statusCode;
          final requiresAuth = requestOptions.extra['requiresAuth'] == true;
          final retryCount =
              (requestOptions.extra['authRetryCount'] as int?) ?? 0;

          if (statusCode == 401 &&
              _sessionManager != null &&
              requiresAuth &&
              retryCount < 1) {
            await _sessionManager.initialize();
            final generationUsed =
                requestOptions.extra['tokenGenerationUsed'] as int?;
            final currentGeneration = _sessionManager.tokenGeneration;
            final retriedWithLatest =
                requestOptions.extra['retriedWithLatestToken'] == true;

            if (!retriedWithLatest &&
                generationUsed != null &&
                generationUsed < currentGeneration &&
                _sessionManager.accessToken != null) {
              if (!_isReplayableRequestData(requestOptions.data)) {
                handler.reject(_notReplayableDioError(requestOptions));
                return;
              }

              final retryOptions = _cloneRequestOptions(requestOptions);
              retryOptions.extra['retriedWithLatestToken'] = true;
              retryOptions.extra['authRetryCount'] = retryCount + 1;
              retryOptions.headers['Authorization'] =
                  'Bearer ${_sessionManager.accessToken}';
              retryOptions.extra['accessTokenUsed'] =
                  _sessionManager.accessToken;
              retryOptions.extra['tokenGenerationUsed'] =
                  _sessionManager.tokenGeneration;

              try {
                handler.resolve(await dio.fetch(retryOptions));
                return;
              } catch (_) {
                handler.next(error);
                return;
              }
            }

            try {
              debugPrint(
                '[API] 401 for ${requestOptions.path}; joining auth refresh '
                'generation=$currentGeneration retryCount=$retryCount',
              );
              final refreshResult = await _sessionManager.refreshOnce();
              if (!_isReplayableRequestData(requestOptions.data)) {
                handler.reject(_notReplayableDioError(requestOptions));
                return;
              }
              final retryOptions = _cloneRequestOptions(requestOptions);
              retryOptions.extra['authRetryCount'] = retryCount + 1;
              retryOptions.headers['Authorization'] =
                  'Bearer ${refreshResult.accessToken}';
              retryOptions.extra['accessTokenUsed'] = refreshResult.accessToken;
              retryOptions.extra['tokenGenerationUsed'] =
                  _sessionManager.tokenGeneration;
              handler.resolve(await dio.fetch(retryOptions));
              return;
            } catch (refreshError) {
              final mapped = refreshError is AuthRefreshFailure
                  ? _sessionManager.mapRefreshFailure(refreshError)
                  : mapError(refreshError);
              final readable = _readableDioError(error, mapped);
              if (requestOptions.extra['skipErrorLog'] != true) {
                unawaited(
                  AppErrorLogService.instance.recordDioException(
                    readable,
                    source: 'api_auth_refresh',
                  ),
                );
              }
              handler.reject(readable);
              return;
            }
          }

          final readable = _readableDioError(error, mapError(error));
          if (requestOptions.extra['skipErrorLog'] != true) {
            unawaited(AppErrorLogService.instance.recordDioException(readable));
          }
          handler.reject(readable);
        },
      ),
    );
  }

  final Dio dio;
  final AuthSessionManager? _sessionManager;

  DioException _readableDioError(DioException error, ApiException mapped) {
    final readable = error.copyWith(message: mapped.message, error: mapped);
    readable.stringBuilder = (_) => mapped.message;
    return readable;
  }

  DioException _notReplayableDioError(RequestOptions options) {
    final error = DioException(
      requestOptions: options,
      error: const RequestNotReplayableException(
        'تم تحديث الجلسة، لكن تعذر إعادة إرسال هذا الطلب تلقائيا. أعد المحاولة يدويا.',
      ),
      message:
          'تم تحديث الجلسة، لكن تعذر إعادة إرسال هذا الطلب تلقائيا. أعد المحاولة يدويا.',
      type: DioExceptionType.unknown,
    );
    error.stringBuilder = (_) => error.message ?? '';
    return error;
  }

  bool _isReplayableRequestData(Object? data) {
    if (data == null) return true;
    if (data is Stream) return false;
    if (data is FormData) return false;
    return true;
  }

  bool _isPublicAuthPath(String requestPath) {
    return requestPath.contains('/api/auth/login') ||
        requestPath.contains('/api/auth/register') ||
        requestPath.contains('/api/auth/forgot-password') ||
        requestPath.contains('/api/auth/reset-password') ||
        requestPath.contains('/api/auth/refresh') ||
        requestPath.contains('/api/app-settings') ||
        requestPath.contains('/health');
  }

  RequestOptions _cloneRequestOptions(RequestOptions request) {
    return request.copyWith(
      headers: Map<String, dynamic>.from(request.headers),
      extra: Map<String, dynamic>.from(request.extra),
    );
  }

  void _syncServerTime(String? dateStr) {
    if (kIsWeb || dateStr == null) return;
    try {
      final serverTime = HttpDate.parse(dateStr).toUtc();
      ApiClient.serverTimeOffset = serverTime.difference(
        DateTime.now().toUtc(),
      );
    } catch (_) {}
  }

  ApiException mapError(Object error) {
    if (error is RequestNotReplayableException) {
      return ApiException(error.message);
    }
    if (error is AuthRefreshFailure) {
      return ApiException(error.message);
    }
    if (error is DioException) {
      final errorPayload = error.error;
      if (errorPayload is ApiException) {
        return errorPayload;
      }
      if (errorPayload is RequestNotReplayableException) {
        return ApiException(errorPayload.message);
      }

      final payload = error.response?.data;
      final statusCode = error.response?.statusCode;
      final requestPath = error.requestOptions.path.toLowerCase();
      final isLoginRequest = requestPath.contains('/api/auth/login');

      String? serverMessage;
      if (payload is Map<String, dynamic>) {
        serverMessage =
            (payload['message'] as String?)?.trim() ??
            (payload['error'] as String?)?.trim();
      }

      if (statusCode == 401) {
        final lower = serverMessage?.toLowerCase() ?? '';
        if (isLoginRequest || lower.contains('invalid username or password')) {
          return const ApiException(
            'اسم المستخدم أو كلمة المرور غير صحيحة.',
            statusCode: 401,
          );
        }
        return const ApiException(
          'انتهت صلاحية الجلسة أو فشل التحقق. سجل الدخول مرة أخرى.',
          statusCode: 401,
        );
      }

      if (statusCode == 403) {
        return const ApiException(
          'ليس لديك صلاحية لتنفيذ هذا الإجراء.',
          statusCode: 403,
        );
      }

      if (statusCode == 404) {
        return const ApiException('العنصر المطلوب غير موجود.', statusCode: 404);
      }

      if (statusCode == 409) {
        return const ApiException(
          'لا يمكن إتمام العملية بسبب تعارض في البيانات.',
          statusCode: 409,
        );
      }

      if (statusCode == 429) {
        return const ApiException(
          'تم تجاوز عدد المحاولات المسموح. حاول مرة أخرى بعد قليل.',
          statusCode: 429,
        );
      }

      if (statusCode != null && statusCode >= 500) {
        return ApiException(
          'الخادم غير متاح حاليا. سيتم تحديث البيانات تلقائيا عند عودة الاتصال.',
          statusCode: statusCode,
        );
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.connectionError) {
        return const ApiException(
          'الخادم غير متاح حاليا. سيتم تحديث البيانات تلقائيا عند عودة الاتصال.',
        );
      }

      if (serverMessage != null && serverMessage.isNotEmpty) {
        return ApiException(serverMessage, statusCode: statusCode);
      }
    }

    if (error is ApiException) {
      return error;
    }
    return ApiException(error.toString());
  }
}

class MissingAuthTokenException implements Exception {
  const MissingAuthTokenException();

  @override
  String toString() => 'Missing or invalid authentication token';
}
