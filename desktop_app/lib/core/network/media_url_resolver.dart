import '../config/app_config.dart';

String _runtimeMediaBaseUrl = AppConfig.defaultApiBaseUrl;

void setMediaBaseUrl(String? baseUrl) {
  final normalized = _normalizeBaseUrl(baseUrl) ?? AppConfig.defaultApiBaseUrl;
  _runtimeMediaBaseUrl = normalized;
}

String get currentMediaBaseUrl => _runtimeMediaBaseUrl;

String? resolveMediaUrl(String? rawUrl) {
  if (rawUrl == null) return null;
  final value = rawUrl.trim();
  if (value.isEmpty) return null;

  return resolveApiUrl(value);
}

String resolveApiUrl(String rawUrl) {
  final value = rawUrl.trim();
  if (value.isEmpty) {
    return value;
  }

  final baseUri = Uri.parse(_runtimeMediaBaseUrl);
  final rawUri = Uri.tryParse(value);
  if (rawUri == null) return value;

  if (!rawUri.hasScheme) {
    final normalizedPath = rawUri.path.startsWith('/')
        ? rawUri.path
        : '/${rawUri.path}';
    return baseUri
        .replace(
          path: normalizedPath,
          query: rawUri.hasQuery ? rawUri.query : null,
          fragment: rawUri.hasFragment ? rawUri.fragment : null,
        )
        .toString();
  }

  const localHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
  if (localHosts.contains(rawUri.host)) {
    return baseUri
        .replace(
          path: rawUri.path,
          query: rawUri.hasQuery ? rawUri.query : null,
        )
        .toString();
  }

  final path = rawUri.path.trim();
  final shouldForceCurrentServer =
      path.startsWith('/api/') || path.startsWith('/uploads/');
  if (shouldForceCurrentServer && _hostsDiffer(baseUri, rawUri)) {
    return baseUri
        .replace(path: path, query: rawUri.hasQuery ? rawUri.query : null)
        .toString();
  }

  if (rawUri.scheme == 'https' && _isPrivateHost(rawUri.host)) {
    return rawUri.replace(scheme: 'http').toString();
  }

  return value;
}

bool _hostsDiffer(Uri left, Uri right) {
  if (left.host.toLowerCase() != right.host.toLowerCase()) {
    return true;
  }
  final leftPort = left.hasPort
      ? left.port
      : _defaultPortForScheme(left.scheme);
  final rightPort = right.hasPort
      ? right.port
      : _defaultPortForScheme(right.scheme);
  return leftPort != rightPort;
}

int _defaultPortForScheme(String scheme) {
  return scheme.toLowerCase() == 'https' ? 443 : 80;
}

String? _normalizeBaseUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  final sanitized = trimmed.replaceFirst(RegExp(r'/+$'), '');
  final parsed = Uri.tryParse(sanitized);
  if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
    return sanitized;
  }
  return null;
}

bool _isPrivateHost(String host) {
  if (host == 'localhost') return true;
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final numbers = parts.map(int.tryParse).toList();
  if (numbers.any((entry) => entry == null)) return false;
  final a = numbers[0]!;
  final b = numbers[1]!;
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168);
}
