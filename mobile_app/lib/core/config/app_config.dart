class AppConfig {
  static const defaultDirectIpPort = int.fromEnvironment(
    'API_DEFAULT_PORT',
    defaultValue: 5000,
  );
  static const defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ismartdbacd.dpdns.org',
  );

  static const connectTimeoutSeconds = 60;
  static const receiveTimeoutSeconds = 60;
}
