class AppServerDefaults {
  const AppServerDefaults({
    required this.desktopBaseUrl,
    required this.mobileBaseUrl,
  });

  final String? desktopBaseUrl;
  final String? mobileBaseUrl;

  factory AppServerDefaults.fromJson(Map<String, dynamic> json) {
    return AppServerDefaults(
      desktopBaseUrl: json['desktopBaseUrl']?.toString(),
      mobileBaseUrl: json['mobileBaseUrl']?.toString(),
    );
  }
}
