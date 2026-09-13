class MobilePrinterOverview {
  const MobilePrinterOverview({
    required this.totals,
    required this.branches,
    required this.printers,
    required this.notifications,
    this.isOffline = false,
  });

  final Map<String, num> totals;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> printers;
  final List<Map<String, dynamic>> notifications;
  final bool isOffline;

  MobilePrinterOverview copyWith({
    Map<String, num>? totals,
    List<Map<String, dynamic>>? branches,
    List<Map<String, dynamic>>? printers,
    List<Map<String, dynamic>>? notifications,
    bool? isOffline,
  }) {
    return MobilePrinterOverview(
      totals: totals ?? this.totals,
      branches: branches ?? this.branches,
      printers: printers ?? this.printers,
      notifications: notifications ?? this.notifications,
      isOffline: isOffline ?? this.isOffline,
    );
  }

  static const empty = MobilePrinterOverview(
    totals: <String, num>{},
    branches: <Map<String, dynamic>>[],
    printers: <Map<String, dynamic>>[],
    notifications: <Map<String, dynamic>>[],
    isOffline: false,
  );

  factory MobilePrinterOverview.fromJson(Map<String, dynamic> json) {
    final dashboard = _map(json['dashboard']);
    return MobilePrinterOverview(
      totals: _numMap(dashboard['totals']),
      branches: _list(dashboard['branches']).map(_map).toList(),
      printers: _list(dashboard['topPrinters']).map(_map).toList(),
      notifications: _list(dashboard['notifications']).map(_map).toList(),
    );
  }
}

Map<String, dynamic> _map(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

Map<String, num> _numMap(Object? raw) {
  return _map(raw).map((key, value) {
    final number = value is num
        ? value
        : num.tryParse(value?.toString() ?? '') ?? 0;
    return MapEntry(key, number);
  });
}

List<dynamic> _list(Object? raw) => raw is List ? raw : const <dynamic>[];
