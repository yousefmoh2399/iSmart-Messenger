import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/services/web_platform_bridge.dart' as web_bridge;

class StoredAuthTokens {
  const StoredAuthTokens({this.accessToken, this.refreshToken});

  final String? accessToken;
  final String? refreshToken;
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

class SessionStore {
  static const _sessionKey = 'desktop_auth_session_v1';
  static const _tokenKey = 'desktop_auth_token';
  static const _refreshTokenKey = 'desktop_refresh_token';
  static const _rememberUsernameKey = 'desktop_remembered_username';
  static const _rememberUserEnabledKey = 'desktop_remember_username_enabled';

  Future<StoredAuthSession?> readSession() async {
    final secureVal = await web_bridge.secureStoreGet(_sessionKey);
    if (secureVal != null && secureVal.isNotEmpty) {
      try {
        return StoredAuthSession.fromJson(
          jsonDecode(secureVal) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final localVal = prefs.getString(_sessionKey);
    if (localVal != null && localVal.isNotEmpty) {
      try {
        final decoded = StoredAuthSession.fromJson(
          jsonDecode(localVal) as Map<String, dynamic>,
        );
        if (await web_bridge.secureStoreSet(_sessionKey, localVal)) {
          await prefs.remove(_sessionKey);
        }
        return decoded;
      } catch (_) {}
    }

    final legacyAccess = await _loadLegacyKey(_tokenKey);
    final legacyRefresh = await _loadLegacyKey(_refreshTokenKey);
    if (legacyAccess != null || legacyRefresh != null) {
      final session = StoredAuthSession(
        accessToken: legacyAccess ?? '',
        refreshToken: legacyRefresh ?? '',
        userId: '',
        generation: 0,
      );
      final jsonStr = jsonEncode(session.toJson());
      bool written = false;
      if (await web_bridge.secureStoreSet(_sessionKey, jsonStr)) {
        await prefs.remove(_sessionKey);
        written = true;
      } else {
        await prefs.setString(_sessionKey, jsonStr);
        written = true;
      }

      if (written) {
        final verify =
            await web_bridge.secureStoreGet(_sessionKey) ??
            prefs.getString(_sessionKey);
        if (verify != null && verify.isNotEmpty) {
          await _clearLegacyTokens();
        }
      }
      return session;
    }

    return null;
  }

  Future<void> writeSession(StoredAuthSession session) async {
    final jsonStr = jsonEncode(session.toJson());
    final prefs = await SharedPreferences.getInstance();
    if (await web_bridge.secureStoreSet(_sessionKey, jsonStr)) {
      await prefs.remove(_sessionKey);
      await _clearLegacyTokens();
      return;
    }
    await prefs.setString(_sessionKey, jsonStr);
    await _clearLegacyTokens();
  }

  Future<void> saveToken(String token) async {
    final current = await readSession();
    await writeSession(
      StoredAuthSession(
        accessToken: token,
        refreshToken: current?.refreshToken ?? '',
        userId: current?.userId ?? '',
        generation: (current?.generation ?? 0) + 1,
      ),
    );
  }

  Future<StoredAuthTokens> readTokens() async {
    final session = await readSession();
    return StoredAuthTokens(
      accessToken: session?.accessToken,
      refreshToken: session?.refreshToken,
    );
  }

  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
    int? generation,
  }) async {
    final current = await readSession();
    await writeSession(
      StoredAuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userId ?? current?.userId ?? '',
        generation: generation ?? ((current?.generation ?? 0) + 1),
      ),
    );
  }

  Future<String?> loadToken() async {
    final session = await readSession();
    return session?.accessToken.isNotEmpty == true
        ? session!.accessToken
        : null;
  }

  Future<void> saveRefreshToken(String refreshToken) async {
    final current = await readSession();
    await writeSession(
      StoredAuthSession(
        accessToken: current?.accessToken ?? '',
        refreshToken: refreshToken,
        userId: current?.userId ?? '',
        generation: (current?.generation ?? 0) + 1,
      ),
    );
  }

  Future<String?> loadRefreshToken() async {
    final session = await readSession();
    return session?.refreshToken.isNotEmpty == true
        ? session!.refreshToken
        : null;
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await web_bridge.secureStoreDelete(_sessionKey);
    await prefs.remove(_sessionKey);
    await _clearLegacyTokens();
  }

  Future<void> _clearLegacyTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await web_bridge.secureStoreDelete(_tokenKey);
    await web_bridge.secureStoreDelete(_refreshTokenKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Future<String?> _loadLegacyKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final secureVal = await web_bridge.secureStoreGet(key);
    if (secureVal != null && secureVal.isNotEmpty) {
      return secureVal;
    }
    return prefs.getString(key);
  }

  Future<void> saveRememberedUsername(String username, bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberUserEnabledKey, remember);
    if (remember) {
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
}
