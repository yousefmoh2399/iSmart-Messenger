import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_server_defaults.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class AppSettingsRepository {
  AppSettingsRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;
  static const _cacheKey = 'desktop_app_server_defaults_cache_v1';

  Future<AppServerDefaults>? _inFlight;
  AppServerDefaults? _cachedSettings;

  Future<AppServerDefaults> fetchDefaults({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_cachedSettings != null) {
        return _cachedSettings!;
      }
      final local = await loadCachedDefaults();
      if (local != null) {
        _cachedSettings = local;
        return local;
      }
    }

    final active = _inFlight;
    if (active != null) return active;

    late final Future<AppServerDefaults> request;

    request = _fetchDefaultsFromApi()
        .then((settings) async {
          _cachedSettings = settings;
          await saveCachedDefaults(settings);
          return settings;
        })
        .catchError((Object err) async {
          // Do NOT cache the error. If a request fails, we fall back to cache.
          final local = _cachedSettings ?? await loadCachedDefaults();
          if (local != null) {
            return local;
          }
          throw err;
        })
        .whenComplete(() {
          if (identical(_inFlight, request)) {
            _inFlight = null;
          }
        });

    _inFlight = request;
    return request;
  }

  Future<AppServerDefaults> _fetchDefaultsFromApi() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/api/app-settings',
      options: Options(
        extra: {'requiresAuth': false, 'requestSource': 'appBootstrap'},
      ),
    );
    final payload = response.data?['settings'];
    if (payload is Map<String, dynamic>) {
      return AppServerDefaults.fromJson(payload);
    }
    throw const ApiException('Invalid settings payload');
  }

  Future<AppServerDefaults> updateDefaults({
    required String token,
    String? desktopBaseUrl,
    String? mobileBaseUrl,
    String? snipeitUrl,
    List<AppServerTarget>? serverTargets,
    bool? showServersShortcut,
  }) async {
    final data = <String, dynamic>{
      'desktopBaseUrl': desktopBaseUrl,
      'mobileBaseUrl': mobileBaseUrl,
      'snipeitUrl': snipeitUrl,
      'serverTargets': serverTargets?.map((entry) => entry.toJson()).toList(),
    };
    if (showServersShortcut != null) {
      data['showServersShortcut'] = showServersShortcut;
    }
    final response = await _apiClient.dio.put<Map<String, dynamic>>(
      '/api/admin/app-settings',
      data: data,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        extra: {'requestSource': 'adminSettings'},
      ),
    );
    final payload = response.data?['settings'];
    if (payload is Map<String, dynamic>) {
      final defaults = AppServerDefaults.fromJson(payload);
      _cachedSettings = defaults;
      await saveCachedDefaults(defaults);
      return defaults;
    }
    final local = _cachedSettings ?? await loadCachedDefaults();
    return local ?? AppServerDefaults.fallback;
  }

  Future<AppServerDefaults?> loadCachedDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppServerDefaults.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveCachedDefaults(AppServerDefaults defaults) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(defaults.toJson()));
    } catch (_) {}
  }
}
