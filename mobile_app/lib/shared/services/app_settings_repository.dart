import '../models/app_server_defaults.dart';
import '../../core/network/api_client.dart';
import 'package:dio/dio.dart';

class AppSettingsRepository {
  AppSettingsRepository({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AppServerDefaults>? _inFlight;
  AppServerDefaults? _cachedSettings;

  Future<AppServerDefaults> fetchDefaults({bool forceRefresh = false}) {
    if (!forceRefresh && _cachedSettings != null) {
      return Future.value(_cachedSettings!);
    }

    final active = _inFlight;
    if (active != null) return active;

    late final Future<AppServerDefaults> request;

    request = _fetchDefaultsFromApi()
        .then((settings) {
          _cachedSettings = settings;
          return settings;
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
    return const AppServerDefaults(desktopBaseUrl: null, mobileBaseUrl: null);
  }
}
