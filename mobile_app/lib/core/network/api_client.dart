import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../features/auth/data/auth_repository.dart';
import '../../shared/services/app_error_log_service.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
  static Duration serverTimeOffset = Duration.zero;

  ApiClient({required String baseUrl, AuthRepository? authRepository})
    : dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(
            seconds: AppConfig.connectTimeoutSeconds,
          ),
          receiveTimeout: const Duration(
            seconds: AppConfig.receiveTimeoutSeconds,
          ),
          sendTimeout: const Duration(seconds: AppConfig.receiveTimeoutSeconds),
        ),
      ),
      _authRepository = authRepository {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final requestPath = options.path.toLowerCase();
          final isPublic =
              requestPath.contains('/api/auth/login') ||
              requestPath.contains('/api/auth/refresh') ||
              requestPath.contains('/api/app-settings') ||
              requestPath.contains('/health');

          options.extra['requiresAuth'] ??= !isPublic;

          String? tokenFingerprint;

          if (_authRepository != null &&
              options.extra['requiresAuth'] == true) {
            try {
              final token = await _authRepository.getValidToken();
              if (token == null || token.isEmpty) {
                handler.reject(
                  _apiExceptionDioError(
                    options,
                    const ApiException(
                      'انتهت صلاحية الجلسة أو فشل التحقق. سجل الدخول مرة أخرى.',
                      statusCode: 401,
                    ),
                  ),
                );
                return;
              }
              options.headers['Authorization'] = 'Bearer $token';
              final generation = await _authRepository.getGeneration();
              options.extra['tokenGenerationUsed'] = generation;
              tokenFingerprint =
                  '${token.length}:${token.substring(max(0, token.length - 6))}';
            } catch (error) {
              handler.reject(
                _apiExceptionDioError(
                  options,
                  error is ApiException
                      ? error
                      : const ApiException(
                          'انتهت صلاحية الجلسة أو فشل التحقق. سجل الدخول مرة أخرى.',
                          statusCode: 401,
                        ),
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

          handler.next(options);
        },
        onResponse: (response, handler) {
          _syncServerTime(response.headers.value('date'));
          handler.next(response);
        },
        onError: (error, handler) async {
          _syncServerTime(error.response?.headers.value('date'));

          final requestOptions = error.requestOptions;
          final alreadyRetried =
              requestOptions.extra['retriedAfterRefresh'] == true;
          final isRefreshRequest = requestOptions.path.contains(
            '/api/auth/refresh',
          );

          // Handle 401 errors by attempting token refresh once per request.
          if (error.response?.statusCode == 401 &&
              _authRepository != null &&
              !alreadyRetried &&
              !isRefreshRequest) {
            try {
              final refreshed = await _refreshAccessToken();
              final token = await _authRepository.getToken();
              if (refreshed && token != null && token.isNotEmpty) {
                final options = requestOptions;
                options.extra['retriedAfterRefresh'] = true;
                options.headers['Authorization'] = 'Bearer $token';
                final response = await dio.fetch(options);
                handler.resolve(response);
                return;
              }
            } catch (refreshError) {
              debugPrint('Token refresh failed: $refreshError');
            }
          }

          // Retry once on network errors (timeout, connection error)
          final isNetworkError =
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError;
          final alreadyRetriedNetwork =
              requestOptions.extra['retriedNetwork'] == true;
          final isTransferEndpoint =
              requestOptions.path.toLowerCase().contains('/transfers') ||
              requestOptions.path.toLowerCase().contains('/upload');

          if (isNetworkError && !alreadyRetriedNetwork && !isTransferEndpoint) {
            requestOptions.extra['retriedNetwork'] = true;
            await Future.delayed(const Duration(seconds: 2));
            try {
              final response = await dio.fetch(requestOptions);
              return handler.resolve(response);
            } catch (retryError) {
              return handler.next(error);
            }
          }

          final mapped = mapError(error);
          final readable = _readableDioError(error, mapped);
          if (requestOptions.extra['skipErrorLog'] != true) {
            unawaited(AppErrorLogService.instance.recordDioException(readable));
          }
          handler.reject(readable);
        },
      ),
    );
  }

  final Dio dio;
  final AuthRepository? _authRepository;
  Future<bool>? _refreshFuture;

  Future<bool> _refreshAccessToken() async {
    if (_refreshFuture != null) {
      return _refreshFuture!;
    }

    _refreshFuture = () async {
      await _authRepository!.refreshToken();
      final token = await _authRepository.getToken();
      return token != null && token.isNotEmpty;
    }();

    try {
      return await _refreshFuture!;
    } finally {
      _refreshFuture = null;
    }
  }

  DioException _readableDioError(DioException error, ApiException mapped) {
    final readable = error.copyWith(message: mapped.message, error: mapped);
    readable.stringBuilder = (_) => mapped.message;
    return readable;
  }

  DioException _apiExceptionDioError(
    RequestOptions options,
    ApiException error,
  ) {
    final readable = DioException(
      requestOptions: options,
      error: error,
      message: error.message,
      type: DioExceptionType.unknown,
    );
    readable.stringBuilder = (_) => error.message;
    return readable;
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
    if (error is DioException) {
      final errorPayload = error.error;
      if (errorPayload is ApiException) {
        return errorPayload;
      }
      final payload = error.response?.data;
      final statusCode = error.response?.statusCode;
      final requestPath = error.requestOptions.path.toLowerCase();
      final isLoginRequest = requestPath.contains('/api/auth/login');

      if (payload is Map<String, dynamic> && payload['message'] is String) {
        final rawMessage = (payload['message'] as String).trim();
        final lowerMessage = rawMessage.toLowerCase();
        if (statusCode == 401 &&
            (isLoginRequest ||
                lowerMessage.contains('invalid username or password'))) {
          return const ApiException(
            'اسم المستخدم أو كلمة المرور غير صحيحة.',
            statusCode: 401,
          );
        }
        if (statusCode == 401) {
          return const ApiException(
            'انتهت صلاحية الجلسة أو فشل التحقق. سجل الدخول مرة أخرى.',
            statusCode: 401,
          );
        }
        return ApiException(
          _translateServerMessage(
            rawMessage,
            statusCode: statusCode,
            requestPath: requestPath,
          ),
          statusCode: statusCode,
        );
      }

      if (statusCode == 401) {
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
        return const ApiException(
          'الخادم غير متاح حاليا. جاري العمل على الإصلاح، وسيتم تحديث البيانات تلقائيا عند عودة الاتصال.',
        );
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return const ApiException(
          'الخادم غير متاح حاليا. جاري العمل على الإصلاح، وسيتم تحديث البيانات تلقائيا عند عودة الاتصال.',
        );
      }

      if (error.type == DioExceptionType.connectionError) {
        return const ApiException(
          'الخادم غير متاح حاليا. جاري العمل على الإصلاح، وسيتم تحديث البيانات تلقائيا عند عودة الاتصال.',
        );
      }
    }

    if (error is ApiException) {
      return error;
    }

    return ApiException(error.toString());
  }

  static String _translateServerMessage(
    String message, {
    required int? statusCode,
    required String requestPath,
  }) {
    final normalized = message.trim();
    final lower = normalized.toLowerCase();

    // Common backend strings (keep clients Arabic-first).
    if (statusCode == 429 ||
        lower.contains('too many') ||
        lower.contains('rate limit')) {
      return 'تم تجاوز عدد المحاولات المسموح. حاول مرة أخرى بعد قليل.';
    }

    if (statusCode == 403 &&
        (lower.contains('permission') ||
            lower.contains('admin access required'))) {
      return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
    }

    if (statusCode == 401 &&
        (lower.contains('authentication required') ||
            lower.contains('invalid or expired token') ||
            lower.contains('invalid refresh token') ||
            lower.contains('refresh token expired') ||
            lower.contains('user no longer exists'))) {
      return 'انتهت صلاحية الجلسة أو فشل التحقق. سجل الدخول مرة أخرى.';
    }

    if (statusCode == 404 && lower.contains('not found')) {
      if (lower.contains('department')) {
        return 'القسم المطلوب غير موجود.';
      }
      if (lower.contains('branch')) {
        return 'الفرع المطلوب غير موجود.';
      }
      return 'العنصر المطلوب غير موجود.';
    }

    if (statusCode == 409 && lower.contains('already exists')) {
      if (lower.contains('username')) {
        return 'اسم المستخدم مستخدم بالفعل.';
      }
      if (lower.contains('branch code')) {
        return 'كود الفرع مستخدم بالفعل.';
      }
      if (lower.contains('department code')) {
        return 'كود القسم مستخدم بالفعل.';
      }
      if (lower.contains('role')) {
        return 'اسم الدور مستخدم بالفعل.';
      }
      return 'هذه البيانات موجودة بالفعل.';
    }

    // Fallback: return original message (could already be Arabic).
    return normalized.isEmpty
        ? (statusCode == null
              ? 'حدث خطأ غير متوقع.'
              : 'حدث خطأ غير متوقع (كود: $statusCode).')
        : normalized;
  }
}
