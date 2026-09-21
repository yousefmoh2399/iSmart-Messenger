class AppConfig {
  static const legacyHostedApiBaseUrl = 'http://192.168.100.253:5000';
  static const defaultDirectIpPort = int.fromEnvironment(
    'API_DEFAULT_PORT',
    defaultValue: 5000,
  );
  static const defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.253:5000',
  );
}
