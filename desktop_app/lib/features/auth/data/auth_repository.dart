import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;
import 'auth_session_manager.dart';
import 'session_store.dart';

class AuthRepository {
  AuthRepository(
    this._apiClient,
    this._sessionStore, {
    required AuthSessionManager sessionManager,
    this.onSessionCredentialsChanged,
    this.onSessionCleared,
  }) : _sessionManager = sessionManager;

  final ApiClient _apiClient;
  final SessionStore _sessionStore;
  final AuthSessionManager _sessionManager;
  final VoidCallback? onSessionCredentialsChanged;
  final VoidCallback? onSessionCleared;
  DateTime? _lastSuccessfulRefreshAt;
  String? _lastSuccessfulRefreshAccessToken;

  static const _deviceUidKey = 'desktop_update_device_uid';
  static const _cachedUserKey = 'desktop_cached_authenticated_user';

  String? get currentToken => _sessionManager.accessToken;

  Future<void> _clearSession({bool notifySessionCleared = true}) async {
    try {
      await _sessionManager.clearSessionOnce(reason: 'auth_repository_clear');
    } finally {
      // Chat data is user-sensitive. It must never survive logout, including
      // when the server logout request or session cleanup fails.
      await _clearUserSpecificCaches();
      await _clearCachedUser();
      if (notifySessionCleared) {
        onSessionCleared?.call();
      }
    }
  }

  Future<void> clearLocalSessionForServerChange() async {
    await _clearSession(notifySessionCleared: true);
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

  Future<AppUser?> restoreSession() async {
    await _sessionManager.initialize();
    final token = _sessionManager.accessToken;
    if (token == null || token.isEmpty) return null;
    final cachedUser = await loadCachedUser();

    try {
      final user = await fetchCurrentUser(
        token: token,
        generation: _sessionManager.tokenGeneration,
      );
      await _saveCachedUser(user);
      return user;
    } catch (error) {
      final mapped = _apiClient.mapError(error);
      if (mapped.isUnauthorized) {
        try {
          final refreshed = await refreshToken();
          final refreshedToken = refreshed['token'];
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            final user = await fetchCurrentUser(
              token: refreshedToken,
              generation: _sessionManager.tokenGeneration,
            );
            await _saveCachedUser(user);
            return user;
          }
        } catch (refreshError) {
          final refreshMapped = _apiClient.mapError(refreshError);
          if (refreshMapped.isUnauthorized) {
            await _clearSession();
            return null;
          }
          if (cachedUser != null) {
            return cachedUser;
          }
          return null;
        }

        await _clearSession();
        return null;
      }

      if (cachedUser != null) {
        return cachedUser;
      }
      throw mapped;
    }
  }

  int _latestLoginAttemptId = 0;

  Future<AppUser> login({
    required String username,
    required String password,
    bool rememberUsername = false,
  }) async {
    final attemptId = ++_latestLoginAttemptId;
    try {
      await web_bridge.electronDebugLog('auth', 'login:start', {
        'username': username.trim().toLowerCase(),
        'baseUrl': _apiClient.dio.options.baseUrl,
      });

      final deviceUid = await _loadOrCreateDeviceUid();
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'username': username,
          'password': password,
          'deviceUid': deviceUid,
        },
      );

      final token = response.data?['token'] as String?;
      final refreshToken = response.data?['refreshToken'] as String?;
      if (token == null ||
          token.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        throw const ApiException(
          'استجابة تسجيل الدخول غير صالحة من الخادم.',
          statusCode: 500,
        );
      }

      if (attemptId != _latestLoginAttemptId) {
        throw const StaleLoginAttemptException();
      }

      final previousUser = await loadCachedUser();

      // Atomic Session Swap
      await _sessionManager.updateTokens(
        accessToken: token,
        refreshToken: refreshToken,
        userId: response.data?['user']?['id'] as String?,
      );

      await _sessionStore.saveRememberedUsername(username, rememberUsername);
      final user = AppUser.fromJson(
        response.data?['user'] as Map<String, dynamic>,
      );
      await _saveCachedUser(user);

      if (previousUser != null && previousUser.id != user.id) {
        await _clearUserSpecificCaches();
      }

      await web_bridge.electronDebugLog('auth', 'login:success', {
        'userId': user.id,
        'username': user.username,
      });
      return user;
    } catch (error) {
      await web_bridge.electronDebugLog('auth', 'login:error', {
        'error': error.toString(),
      });
      if (error is StaleLoginAttemptException) {
        rethrow;
      }
      throw _apiClient.mapError(error);
    }
  }

  Future<void> _clearUserSpecificCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('chat_cache_') ||
            key.startsWith('chat_pref_') ||
            key.startsWith('printer_pref_') ||
            key.contains('_cache_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('AuthRepository: Failed to clear user specific caches: $e');
    }
  }

  Future<String?> getToken() async {
    await _sessionManager.initialize();
    return _sessionManager.accessToken;
  }

  Future<String?> getValidToken({
    Duration refreshBefore = const Duration(minutes: 2),
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    if (!_isTokenExpiringSoon(token, refreshBefore)) {
      return token;
    }
    if (_wasJustRefreshed(token)) {
      return token;
    }

    try {
      final refreshed = await refreshToken();
      return refreshed['token'] ?? _sessionManager.accessToken;
    } catch (error) {
      if (error is ApiException && error.isUnauthorized) {
        rethrow;
      }
      final fallbackToken = _sessionManager.accessToken;
      if (fallbackToken != null && fallbackToken.isNotEmpty) {
        return fallbackToken;
      }
      if (error is ApiException) {
        return null;
      }
      rethrow;
    }
  }

  Future<String?> getRefreshToken() async {
    await _sessionManager.initialize();
    return _sessionManager.refreshToken;
  }

  Future<Map<String, String>> refreshToken() async {
    try {
      final result = await _sessionManager.refreshOnce();
      _lastSuccessfulRefreshAt = DateTime.now().toUtc();
      _lastSuccessfulRefreshAccessToken = result.accessToken;
      return {'token': result.accessToken, 'refreshToken': result.refreshToken};
    } catch (error) {
      if (error is AuthRefreshFailure) {
        throw _sessionManager.mapRefreshFailure(error);
      }
      throw _apiClient.mapError(error);
    }
  }

  bool _wasJustRefreshed(String token) {
    final refreshedAt = _lastSuccessfulRefreshAt;
    return _lastSuccessfulRefreshAccessToken == token &&
        refreshedAt != null &&
        DateTime.now().toUtc().difference(refreshedAt) <
            const Duration(seconds: 15);
  }

  bool _isTokenExpiringSoon(String token, Duration refreshBefore) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) {
        return true;
      }
      final normalized = base64Url.normalize(parts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalized)))
              as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) {
        return true;
      }
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
      var effectiveRefreshBefore = refreshBefore;
      final iat = payload['iat'];
      if (iat is num) {
        final issuedAt = DateTime.fromMillisecondsSinceEpoch(
          iat.toInt() * 1000,
          isUtc: true,
        );
        final tokenLifetime = expiry.difference(issuedAt);
        if (tokenLifetime > Duration.zero) {
          final proportionalWindow = Duration(
            milliseconds: (tokenLifetime.inMilliseconds / 5).round(),
          );
          if (proportionalWindow < effectiveRefreshBefore) {
            effectiveRefreshBefore = proportionalWindow;
          }
        }
      }
      final syncedNow = DateTime.now().toUtc().add(ApiClient.serverTimeOffset);
      return expiry.isBefore(syncedNow.add(effectiveRefreshBefore));
    } catch (_) {
      return true;
    }
  }

  Future<AppUser> fetchCurrentUser({
    String? token,
    int? generation,
    String requestSource = 'appBootstrap',
  }) async {
    final resolvedToken = token ?? await getToken();
    final normalizedToken = resolvedToken?.trim();
    if (normalizedToken == null ||
        normalizedToken.isEmpty ||
        normalizedToken.toLowerCase() == 'null') {
      throw const ApiException(
        'Missing authentication token.',
        statusCode: 401,
      );
    }
    final resolvedGen =
        generation ??
        (await _sessionManager.initialize().then(
          (_) => _sessionManager.tokenGeneration,
        ));
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/users/me',
      options: Options(
        headers: {'Authorization': 'Bearer $normalizedToken'},
        extra: {
          'tokenGenerationUsed': resolvedGen,
          'requestSource': requestSource,
        },
      ),
    );
    final user = AppUser.fromJson(
      response.data?['user'] as Map<String, dynamic>,
    );
    await _saveCachedUser(user);
    return user;
  }

  Future<AppUser> updateProfile({
    required String fullName,
    String? password,
  }) async {
    final token = await getToken();
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/users/me',
      data: {
        'fullName': fullName,
        if (password != null && password.trim().isNotEmpty)
          'password': password,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final user = AppUser.fromJson(
      response.data?['user'] as Map<String, dynamic>,
    );
    await _saveCachedUser(user);
    return user;
  }

  Future<AppUser> updateChatPreferences({
    required ChatPreferences chatPreferences,
  }) async {
    final token = await getToken();
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/users/me',
      data: {'chatPreferences': chatPreferences.toJson()},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final user = AppUser.fromJson(
      response.data?['user'] as Map<String, dynamic>,
    );
    await _saveCachedUser(user);
    return user;
  }

  Future<AppUser> uploadAvatar(
    String filePath, {
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    final token = await getToken();
    final resolvedFileName = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : p.basename(filePath);
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/users/me/avatar',
      data: FormData.fromMap({
        'avatar': fileBytes != null
            ? MultipartFile.fromBytes(fileBytes, filename: resolvedFileName)
            : await MultipartFile.fromFile(
                filePath,
                filename: resolvedFileName,
              ),
      }),
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        contentType: 'multipart/form-data',
      ),
    );
    final user = AppUser.fromJson(
      response.data?['user'] as Map<String, dynamic>,
    );
    await _saveCachedUser(user);
    return user;
  }

  Future<void> logout() async {
    final token = await getToken();
    String? deviceUid;
    try {
      deviceUid = await _loadOrCreateDeviceUid();
    } catch (_) {}

    try {
      if (token != null && token.trim().isNotEmpty && deviceUid != null) {
        await _apiClient.dio.post<Map<String, dynamic>>(
          '/api/auth/logout',
          data: {'deviceUid': deviceUid},
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            validateStatus: (code) => code != null && code < 500,
            sendTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            extra: {'requestSource': 'auth.logout'},
          ),
        );
      }
    } catch (error) {
      debugPrint('[AuthRepository] Logout request failed: $error');
    } finally {
      await _clearSession(notifySessionCleared: true);
    }
  }

  Future<void> _saveCachedUser(AppUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedUserKey, jsonEncode(user.toJson()));
  }

  Future<void> _clearCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedUserKey);
  }

  Future<AppUser?> loadCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedUserKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AppUser.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<StoredAuthSession?> getSession() => _sessionStore.readSession();

  Future<String?> loadRememberedUsername() =>
      _sessionStore.loadRememberedUsername();

  Future<bool> isRememberUsernameEnabled() =>
      _sessionStore.isRememberUsernameEnabled();
}

class StaleLoginAttemptException implements Exception {
  const StaleLoginAttemptException();

  @override
  String toString() => 'Stale login attempt';
}
