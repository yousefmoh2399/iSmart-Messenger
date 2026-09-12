import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/app_user.dart';

class AuthRepository {
  AuthRepository(
    this._apiClient, {
    this.onSessionCredentialsChanged,
    this.onSessionCleared,
  });

  final ApiClient _apiClient;
  final VoidCallback? onSessionCredentialsChanged;
  final VoidCallback? onSessionCleared;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Future<Map<String, String>>? _tokenRefreshFuture;
  DateTime? _lastSuccessfulRefreshAt;
  String? _lastSuccessfulRefreshAccessToken;

  static const _sessionKey = 'auth_session_v1';
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _rememberUsernameKey = 'remembered_username';
  static const _rememberUserEnabledKey = 'remember_username_enabled';
  static const _deviceUidKey = 'mobile_update_device_uid';
  static const _cachedUserKey = 'cached_authenticated_user';

  int _latestLoginAttemptId = 0;

  Future<StoredAuthSession?> _readSession() async {
    try {
      final secureVal = await _storage.read(key: _sessionKey);
      if (secureVal != null && secureVal.isNotEmpty) {
        return StoredAuthSession.fromJson(
          jsonDecode(secureVal) as Map<String, dynamic>,
        );
      }
    } catch (_) {}

    try {
      final legacyAccess = await _storage.read(key: _tokenKey);
      final legacyRefresh = await _storage.read(key: _refreshTokenKey);
      if (legacyAccess != null || legacyRefresh != null) {
        final session = StoredAuthSession(
          accessToken: legacyAccess ?? '',
          refreshToken: legacyRefresh ?? '',
          userId: '',
          generation: 0,
        );
        final jsonStr = jsonEncode(session.toJson());
        await _storage.write(key: _sessionKey, value: jsonStr);
        final verify = await _storage.read(key: _sessionKey);
        if (verify != null && verify.isNotEmpty) {
          await _clearLegacyTokens();
        }
        return session;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeSession(StoredAuthSession session) async {
    final jsonStr = jsonEncode(session.toJson());
    await _storage.write(key: _sessionKey, value: jsonStr);
    await _clearLegacyTokens();
  }

  Future<void> _clearLegacyTokens() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _refreshTokenKey);
    } catch (_) {}
  }

  Future<String> _loadOrCreateDeviceUid() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceUidKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final created = const Uuid().v4();
    await prefs.setString(_deviceUidKey, created);
    return created;
  }

  void _notifySessionCredentialsChanged() {
    onSessionCredentialsChanged?.call();
  }

  Future<void> _clearSession() async {
    await _writeSession(
      const StoredAuthSession(
        accessToken: '',
        refreshToken: '',
        userId: '',
        generation: 0,
      ),
    );
    await _clearCachedUser();
    _notifySessionCredentialsChanged();
    onSessionCleared?.call();
  }

  Future<AppUser?> restoreSession() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    final gen = await getGeneration();
    final cachedUser = await loadCachedUser();
    try {
      final user = await fetchCurrentUser(token: token, generation: gen);
      await _saveCachedUser(user);
      return user;
    } catch (error) {
      final mapped = _apiClient.mapError(error);
      if (mapped.isUnauthorized) {
        try {
          await refreshToken();
          final refreshedToken = await getToken();
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            final newGen = await getGeneration();
            final user = await fetchCurrentUser(
              token: refreshedToken,
              generation: newGen,
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

  Future<AppUser> login({
    required String username,
    required String password,
    bool rememberUsername = false,
  }) async {
    final attemptId = ++_latestLoginAttemptId;
    try {
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
      final refreshTokenVal = response.data?['refreshToken'] as String?;
      if (token == null ||
          token.isEmpty ||
          refreshTokenVal == null ||
          refreshTokenVal.isEmpty) {
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
      await _writeSession(
        StoredAuthSession(
          accessToken: token,
          refreshToken: refreshTokenVal,
          userId: response.data?['user']?['id'] as String? ?? '',
          generation: 0,
        ),
      );

      await _saveRememberedUsername(username, rememberUsername);
      final user = AppUser.fromJson(
        response.data?['user'] as Map<String, dynamic>,
      );
      await _saveCachedUser(user);

      if (previousUser != null && previousUser.id != user.id) {
        await _clearUserSpecificCaches();
      }

      _notifySessionCredentialsChanged();
      return user;
    } catch (error) {
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
        if (key.startsWith('chat_pref_') ||
            key.startsWith('printer_pref_') ||
            key.contains('_cache_')) {
          await prefs.remove(key);
        }
      }
    } catch (_) {}
  }

  Future<String?> getToken() async {
    try {
      final session = await _readSession();
      return session?.accessToken.isNotEmpty == true
          ? session!.accessToken
          : null;
    } catch (e) {
      debugPrint(
        'AuthRepository: Keystore corrupted or error reading token: $e',
      );
      await _storage.deleteAll();
      return null;
    }
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

    final refreshed = await _refreshTokenSingleFlight();
    return refreshed['token'] ?? await getToken();
  }

  Future<String?> getRefreshToken() async {
    try {
      final session = await _readSession();
      return session?.refreshToken.isNotEmpty == true
          ? session!.refreshToken
          : null;
    } catch (e) {
      debugPrint(
        'AuthRepository: Keystore corrupted or error reading refresh token: $e',
      );
      await _storage.deleteAll();
      return null;
    }
  }

  Future<Map<String, String>> refreshToken() async {
    final rToken = await getRefreshToken();
    if (rToken == null || rToken.trim().isEmpty) {
      throw const ApiException(
        'لا يوجد رمز تجديد الجلسة. سجّل الدخول مرة أخرى.',
        statusCode: 401,
      );
    }

    try {
      final deviceUid = await _loadOrCreateDeviceUid();
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: {'refreshToken': rToken, 'deviceUid': deviceUid},
      );

      final newToken = response.data?['token'] as String?;
      final newRefreshToken = response.data?['refreshToken'] as String?;
      if (newToken == null ||
          newToken.isEmpty ||
          newRefreshToken == null ||
          newRefreshToken.isEmpty) {
        await _clearSession();
        throw const ApiException(
          'استجابة تجديد الجلسة غير صالحة من الخادم.',
          statusCode: 500,
        );
      }

      final session = await _readSession();
      await _writeSession(
        StoredAuthSession(
          accessToken: newToken,
          refreshToken: newRefreshToken,
          userId: session?.userId ?? '',
          generation: (session?.generation ?? 0) + 1,
        ),
      );
      _notifySessionCredentialsChanged();
      _lastSuccessfulRefreshAt = DateTime.now().toUtc();
      _lastSuccessfulRefreshAccessToken = newToken;

      return {'token': newToken, 'refreshToken': newRefreshToken};
    } catch (error) {
      final mapped = _apiClient.mapError(error);
      if (mapped.isUnauthorized) {
        await _clearSession();
      }
      throw mapped;
    }
  }

  Future<Map<String, String>> _refreshTokenSingleFlight() async {
    if (_tokenRefreshFuture != null) {
      return _tokenRefreshFuture!;
    }
    _tokenRefreshFuture = refreshToken();
    try {
      return await _tokenRefreshFuture!;
    } finally {
      _tokenRefreshFuture = null;
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
    final resolvedGen = generation ?? (await getGeneration());
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

  Future<AppUser> uploadAvatar(String filePath) async {
    final token = await getToken();
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/api/users/me/avatar',
      data: FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          filePath,
          filename: p.basename(filePath),
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
      if (token != null && token.trim().isNotEmpty) {
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
      await _clearSession();
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

  Future<void> _saveRememberedUsername(
    String username,
    bool rememberUsername,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberUserEnabledKey, rememberUsername);
    if (rememberUsername) {
      await prefs.setString(_rememberUsernameKey, username.trim());
    } else {
      await prefs.remove(_rememberUsernameKey);
    }
  }

  Future<String?> loadRememberedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberUserEnabledKey) ?? false;
    if (!remember) {
      return null;
    }
    return prefs.getString(_rememberUsernameKey);
  }

  Future<bool> isRememberUsernameEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberUserEnabledKey) ?? false;
  }

  Future<StoredAuthSession?> getSession() => _readSession();

  Future<int> getGeneration() async {
    final session = await _readSession();
    return session?.generation ?? 0;
  }
}

class StoredAuthSession {
  const StoredAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.generation,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final int generation;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'userId': userId,
    'generation': generation,
  };

  factory StoredAuthSession.fromJson(Map<String, dynamic> json) {
    return StoredAuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      generation: (json['generation'] as num?)?.toInt() ?? 0,
    );
  }
}

class StaleLoginAttemptException implements Exception {
  const StaleLoginAttemptException();

  @override
  String toString() => 'Stale login attempt';
}
