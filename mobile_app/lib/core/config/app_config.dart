class AppConfig {
  static const defaultDirectIpPort = int.fromEnvironment(
    'API_DEFAULT_PORT',
    defaultValue: 4000,
  );
  static const defaultApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://ismartdbacd.dpdns.org',
  );

  static const connectTimeoutSeconds = 20;
  static const receiveTimeoutSeconds = 60;
}
