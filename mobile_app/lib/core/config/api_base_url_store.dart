import 'package:shared_preferences/shared_preferences.dart';
import 'app_config.dart';

class ApiBaseUrlStore {
  static const _apiBaseUrlKey = 'mobile_api_base_url_v2';
  static const _apiBaseUrlOverrideKey = 'mobile_api_base_url_override_v1';
  static const _adminDefaultBaseUrlKey = 'mobile_api_base_url_admin_default_v1';
  static const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

  Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getString(_apiBaseUrlKey);
    final adminDefault = prefs.getString(_adminDefaultBaseUrlKey);
    final overrideFlag = prefs.getBool(_apiBaseUrlOverrideKey);
    final hasSavedValue = savedValue != null && savedValue.trim().isNotEmpty;
    final isOverride = overrideFlag ?? hasSavedValue;
    final normalized = normalize(savedValue);
    final normalizedAdmin = normalize(adminDefault);

    if (_shouldFallbackToDefault(normalized)) {
      await prefs.remove(_apiBaseUrlKey);
      await prefs.remove(_apiBaseUrlOverrideKey);
      if (!_shouldFallbackToDefault(normalizedAdmin) &&
          normalizedAdmin != null) {
        return normalizedAdmin;
      }
      return AppConfig.defaultApiBaseUrl;
    }
    if (isOverride) {
      return normalized ?? AppConfig.defaultApiBaseUrl;
    }
    if (normalizedAdmin != null && !_shouldFallbackToDefault(normalizedAdmin)) {
      return normalizedAdmin;
    }
    return normalized ?? AppConfig.defaultApiBaseUrl;
  }

  Future<void> save(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _apiBaseUrlKey,
      normalize(value) ?? AppConfig.defaultApiBaseUrl,
    );
    await prefs.setBool(_apiBaseUrlOverrideKey, true);
  }

  Future<void> saveAdminDefault(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _adminDefaultBaseUrlKey,
      normalize(value) ?? AppConfig.defaultApiBaseUrl,
    );
  }

  Future<bool> isUserOverrideEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final flag = prefs.getBool(_apiBaseUrlOverrideKey);
    if (flag != null) {
      return flag;
    }
    final savedValue = prefs.getString(_apiBaseUrlKey);
    return savedValue != null && savedValue.trim().isNotEmpty;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiBaseUrlKey);
    await prefs.remove(_apiBaseUrlOverrideKey);
  }

  static String? normalize(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final withoutTrailingSlash = trimmed.replaceFirst(RegExp(r'/+$'), '');
    final parsed = Uri.tryParse(withoutTrailingSlash);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return withoutTrailingSlash;
    }

    final candidate = withoutTrailingSlash.replaceFirst(RegExp(r'^/+'), '');
    final looksLikeHost =
        !candidate.contains(RegExp(r'\s')) &&
        (candidate == 'localhost' ||
            candidate.contains('.') ||
            candidate.contains(':'));
    if (!looksLikeHost) {
      return withoutTrailingSlash;
    }

    final withHttp = 'http://$candidate';
    final normalized = Uri.tryParse(withHttp);
    if (normalized != null && normalized.host.isNotEmpty) {
      if (!normalized.hasPort && _shouldUseDirectIpPort(normalized.host)) {
        return normalized
            .replace(port: AppConfig.defaultDirectIpPort)
            .toString()
            .replaceFirst(RegExp(r'/$'), '');
      }
      return withHttp;
    }

    return withoutTrailingSlash;
  }

  static bool _shouldFallbackToDefault(String? savedValue) {
    if (savedValue == null) {
      return false;
    }

    final savedUri = Uri.tryParse(savedValue);
    final defaultUri = Uri.tryParse(AppConfig.defaultApiBaseUrl);
    if (savedUri == null || defaultUri == null) {
      return false;
    }

    final savedHost = savedUri.host.toLowerCase();
    final defaultHost = defaultUri.host.toLowerCase();
    final defaultIsLocal = _localHosts.contains(defaultHost);
    return _localHosts.contains(savedHost) && !defaultIsLocal;
  }

  static bool _shouldUseDirectIpPort(String host) {
    final lowerHost = host.toLowerCase();
    if (_localHosts.contains(lowerHost)) {
      return true;
    }
    final parts = lowerHost.split('.');
    if (parts.length != 4) {
      return false;
    }
    return parts.every((part) {
      final value = int.tryParse(part);
      return value != null && value >= 0 && value <= 255;
    });
  }
}
