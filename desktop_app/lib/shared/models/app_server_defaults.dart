class AppServerDefaults {
  const AppServerDefaults({
    required this.desktopBaseUrl,
    required this.mobileBaseUrl,
    required this.snipeitUrl,
    required this.serverTargets,
    required this.showServersShortcut,
  });

  final String? desktopBaseUrl;
  final String? mobileBaseUrl;
  final String? snipeitUrl;
  final List<AppServerTarget> serverTargets;
  final bool showServersShortcut;

  static const fallback = AppServerDefaults(
    desktopBaseUrl: null,
    mobileBaseUrl: null,
    snipeitUrl: null,
    serverTargets: <AppServerTarget>[],
    showServersShortcut: true,
  );

  factory AppServerDefaults.fromJson(Map<String, dynamic> json) {
    final targetsJson = json['serverTargets'] as List<dynamic>? ?? const [];
    return AppServerDefaults(
      desktopBaseUrl: json['desktopBaseUrl']?.toString(),
      mobileBaseUrl: json['mobileBaseUrl']?.toString(),
      snipeitUrl: json['snipeitUrl']?.toString(),
      serverTargets: targetsJson
          .whereType<Map<String, dynamic>>()
          .map(AppServerTarget.fromJson)
          .toList(),
      showServersShortcut: json['showServersShortcut'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'desktopBaseUrl': desktopBaseUrl,
    'mobileBaseUrl': mobileBaseUrl,
    'snipeitUrl': snipeitUrl,
    'serverTargets': serverTargets.map((entry) => entry.toJson()).toList(),
    'showServersShortcut': showServersShortcut,
  };
}

class AppServerTarget {
  const AppServerTarget({
    required this.title,
    required this.baseUrl,
    required this.ports,
  });

  final String title;
  final String baseUrl;
  final List<int> ports;

  factory AppServerTarget.fromJson(Map<String, dynamic> json) {
    final portsJson = json['ports'] as List<dynamic>? ?? const [];
    return AppServerTarget(
      title: json['title']?.toString() ?? '',
      baseUrl: json['baseUrl']?.toString() ?? '',
      ports: portsJson
          .map((entry) => int.tryParse(entry.toString()))
          .whereType<int>()
          .where((entry) => entry > 0)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'baseUrl': baseUrl,
    'ports': ports,
  };
}
