import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_exception.dart';
import 'session_store.dart';

class RefreshResult {
  const RefreshResult({
    required this.accessToken,
    required this.refreshToken,
    this.reusedLatestSession = false,
  });

  final String accessToken;
  final String refreshToken;
  final bool reusedLatestSession;
}

sealed class AuthRefreshFailure implements Exception {
  const AuthRefreshFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class InvalidRefreshTokenException extends AuthRefreshFailure {
  const InvalidRefreshTokenException([
    super.message = 'Refresh token is invalid or expired.',
  ]);
}

class SessionAlreadyClearedException extends AuthRefreshFailure {
  const SessionAlreadyClearedException([
    super.message = 'Session was already cleared.',
  ]);
}

class RefreshNetworkException extends AuthRefreshFailure {
  const RefreshNetworkException([
    super.message = 'Refresh failed because the server is unreachable.',
  ]);
}

class RefreshServerException extends AuthRefreshFailure {
  const RefreshServerException(this.statusCode)
    : super('Refresh failed because the server returned an error.');

  final int? statusCode;
}

class RequestNotReplayableException implements Exception {
  const RequestNotReplayableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthRefreshService {
  AuthRefreshService({required String baseUrl, Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              sendTimeout: kIsWeb ? null : const Duration(seconds: 15),
            ),
          );

  final Dio dio;
  static const _deviceUidKey = 'desktop_update_device_uid';

  Future<RefreshResult> refresh({required String refreshToken}) async {
    try {
      final deviceUid = await _loadOrCreateDeviceUid();
      final response = await dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: {'refreshToken': refreshToken, 'deviceUid': deviceUid},
      );
      final accessToken = response.data?['token'] as String?;
      final newRefreshToken = response.data?['refreshToken'] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          newRefreshToken == null ||
          newRefreshToken.isEmpty) {
        throw const RefreshServerException(200);
      }
      return RefreshResult(
        accessToken: accessToken,
        refreshToken: newRefreshToken,
      );
    } on DioException catch (error) {
      if (_isRefreshTokenRejected(error)) {
        throw const InvalidRefreshTokenException();
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        throw const RefreshNetworkException();
      }
      final statusCode = error.response?.statusCode;
      if (statusCode != null && statusCode >= 500) {
        throw RefreshServerException(statusCode);
      }
      rethrow;
    }
  }

  bool _isRefreshTokenRejected(DioException error) {
    final status = error.response?.statusCode;
    return status == 401 || status == 403;
  }

  Future<String> _loadOrCreateDeviceUid() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceUidKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final created = 'dev-$hex';
    await prefs.setString(_deviceUidKey, created);
    return created;
  }
}

class AuthSessionManager {
  AuthSessionManager({
    required SessionStore tokenStorage,
    required AuthRefreshService refreshService,
    this.onSessionCredentialsChanged,
    this.onSessionCleared,
  }) : _tokenStorage = tokenStorage,
       _refreshService = refreshService;

  final SessionStore _tokenStorage;
  final AuthRefreshService _refreshService;
  final VoidCallback? onSessionCredentialsChanged;
  final VoidCallback? onSessionCleared;

  String? _accessToken;
  String? _refreshToken;
  Future<void>? _initializeFuture;
  Future<RefreshResult>? _refreshFuture;
  int _tokenGeneration = 0;
  bool _initialized = false;
  bool _sessionCleared = false;
  int _refreshOperationCounter = 0;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  int get tokenGeneration => _tokenGeneration;
  bool get isInitialized => _initialized;

  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }
    return _initializeFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    final session = await _tokenStorage.readSession();
    _accessToken = session?.accessToken;
    _refreshToken = session?.refreshToken;
    _tokenGeneration = session?.generation ?? 0;
    _initialized = true;
    _sessionCleared = false;
    _initializeFuture = null;
  }

  Future<RefreshResult> refreshOnce() {
    final running = _refreshFuture;
    if (running != null) {
      debugPrint(
        '[AUTH] auth_refresh_join operation=existing generation=$_tokenGeneration',
      );
      return running;
    }

    final operationId = ++_refreshOperationCounter;
    final future = _performRefresh(operationId);
    _refreshFuture = future;
    unawaited(
      future
          .whenComplete(() {
            if (identical(_refreshFuture, future)) {
              _refreshFuture = null;
            }
          })
          .then<void>((_) {}, onError: (_) {}),
    );
    return future;
  }

  Future<RefreshResult> _performRefresh(int operationId) async {
    await initialize();
    final refreshTokenAtStart = _refreshToken;
    final generationAtStart = _tokenGeneration;

    debugPrint(
      '[AUTH] auth_refresh_start operation=$operationId generation=$generationAtStart',
    );

    if (refreshTokenAtStart == null || refreshTokenAtStart.isEmpty) {
      await clearSessionOnce(reason: 'missing_refresh_token');
      throw const InvalidRefreshTokenException();
    }

    try {
      final result = await _refreshService.refresh(
        refreshToken: refreshTokenAtStart,
      );

      if (_sessionCleared) {
        throw const SessionAlreadyClearedException();
      }

      if (generationAtStart != _tokenGeneration) {
        return _latestRefreshResult(reusedLatestSession: true);
      }

      await updateTokens(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
      );

      debugPrint(
        '[AUTH] auth_refresh_success operation=$operationId generation=$_tokenGeneration reused=false',
      );
      return result;
    } on InvalidRefreshTokenException {
      if (generationAtStart != _tokenGeneration) {
        return _latestRefreshResult(reusedLatestSession: true);
      }
      await clearSessionOnce(reason: 'refresh_token_rejected');
      rethrow;
    } on AuthRefreshFailure {
      if (generationAtStart != _tokenGeneration) {
        return _latestRefreshResult(reusedLatestSession: true);
      }
      rethrow;
    } on DioException {
      if (generationAtStart != _tokenGeneration) {
        return _latestRefreshResult(reusedLatestSession: true);
      }
      rethrow;
    }
  }

  RefreshResult _latestRefreshResult({required bool reusedLatestSession}) {
    final accessToken = _accessToken;
    final refreshToken = _refreshToken;
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      throw const SessionAlreadyClearedException();
    }
    return RefreshResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      reusedLatestSession: reusedLatestSession,
    );
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
    int? generation,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _tokenGeneration = generation ?? (_tokenGeneration + 1);
    _sessionCleared = false;
    await _tokenStorage.writeTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userId,
      generation: _tokenGeneration,
    );
    onSessionCredentialsChanged?.call();
  }

  Future<void> clearSessionOnce({String reason = 'unknown'}) async {
    if (_sessionCleared) {
      return;
    }
    _sessionCleared = true;
    _accessToken = null;
    _refreshToken = null;
    _tokenGeneration++;
    await _tokenStorage.clearToken();
    debugPrint('[AUTH] auth_session_cleared reason=$reason');
    onSessionCredentialsChanged?.call();
    onSessionCleared?.call();
  }

  ApiException mapRefreshFailure(Object error) {
    if (error is InvalidRefreshTokenException ||
        error is SessionAlreadyClearedException) {
      return const ApiException(
        'انتهت صلاحية الجلسة أو فشل التحقق. سجل الدخول مرة أخرى.',
        statusCode: 401,
      );
    }
    if (error is RefreshNetworkException) {
      return const ApiException(
        'الخادم غير متاح حاليا. سيتم الاحتفاظ بالجلسة والمحاولة لاحقا.',
      );
    }
    if (error is RefreshServerException) {
      return ApiException(
        'الخادم غير متاح حاليا. سيتم الاحتفاظ بالجلسة والمحاولة لاحقا.',
        statusCode: error.statusCode,
      );
    }
    return ApiException(error.toString());
  }
}
