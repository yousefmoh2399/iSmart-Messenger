class PrinterBranchItem {
  const PrinterBranchItem({
    required this.id,
    required this.name,
    required this.code,
    required this.networkRange,
    required this.location,
    required this.status,
    required this.lastSyncAt,
  });

  final String id;
  final String name;
  final String code;
  final String networkRange;
  final String location;
  final String status;
  final DateTime? lastSyncAt;

  factory PrinterBranchItem.fromJson(Map<String, dynamic> json) {
    return PrinterBranchItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      networkRange: json['networkRange']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      lastSyncAt: DateTime.tryParse(json['lastSyncAt']?.toString() ?? ''),
    );
  }
}

class PrinterItem {
  const PrinterItem({
    required this.id,
    required this.branchId,
    required this.branchName,
    required this.name,
    required this.ipAddress,
    required this.hostname,
    required this.vendor,
    required this.model,
    required this.serialNumber,
    required this.status,
    required this.lastSyncAt,
    required this.counters,
    required this.lifetimeCounters,
    required this.tonerLevels,
    required this.maintenance,
    required this.extendedDetails,
  });

  final String id;
  final String branchId;
  final String branchName;
  final String name;
  final String ipAddress;
  final String hostname;
  final String vendor;
  final String model;
  final String serialNumber;
  final String status;
  final DateTime? lastSyncAt;
  final Map<String, num> counters;
  final Map<String, num> lifetimeCounters;
  final Map<String, dynamic> tonerLevels;
  final Map<String, dynamic> maintenance;
  final Map<String, dynamic> extendedDetails;

  factory PrinterItem.fromJson(Map<String, dynamic> json) {
    return PrinterItem(
      id: json['id']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      branchName: json['branchName']?.toString() ?? '',
      name: json['printerName']?.toString() ?? json['name']?.toString() ?? '',
      ipAddress: json['ipAddress']?.toString() ?? '',
      hostname: json['hostname']?.toString() ?? '',
      vendor: json['vendor']?.toString() ?? 'SNMP',
      model: json['model']?.toString() ?? '',
      serialNumber: json['serialNumber']?.toString() ?? '',
      status: json['status']?.toString() ?? 'offline',
      lastSyncAt: DateTime.tryParse(json['lastSyncAt']?.toString() ?? ''),
      counters: _numMap(json['counters']),
      lifetimeCounters: _numMap(json['lifetimeCounters']),
      tonerLevels: _dynamicMap(json['tonerLevels']),
      maintenance: _dynamicMap(json['maintenance']),
      extendedDetails: _dynamicMap(json['extendedDetails']),
    );
  }
}

class PrinterDashboardData {
  const PrinterDashboardData({
    required this.totals,
    required this.branches,
    required this.printers,
    required this.notifications,
    required this.activity,
  });

  final Map<String, num> totals;
  final List<PrinterBranchItem> branches;
  final List<PrinterItem> printers;
  final List<Map<String, dynamic>> notifications;
  final List<Map<String, dynamic>> activity;

  static const empty = PrinterDashboardData(
    totals: <String, num>{},
    branches: <PrinterBranchItem>[],
    printers: <PrinterItem>[],
    notifications: <Map<String, dynamic>>[],
    activity: <Map<String, dynamic>>[],
  );

  factory PrinterDashboardData.fromJson(Map<String, dynamic> json) {
    final dashboard = _dynamicMap(json['dashboard']);
    return PrinterDashboardData(
      totals: _numMap(dashboard['totals']),
      branches: _list(
        dashboard['branches'],
      ).map((entry) => PrinterBranchItem.fromJson(_dynamicMap(entry))).toList(),
      printers: _list(
        dashboard['topPrinters'],
      ).map((entry) => PrinterItem.fromJson(_dynamicMap(entry))).toList(),
      notifications: _list(
        dashboard['notifications'],
      ).map(_dynamicMap).toList(),
      activity: _list(dashboard['activity']).map(_dynamicMap).toList(),
    );
  }
}

class PrinterOverviewData {
  const PrinterOverviewData({
    required this.dashboard,
    required this.branches,
    required this.printers,
    required this.logs,
    this.isOffline = false,
  });

  final PrinterDashboardData dashboard;
  final List<PrinterBranchItem> branches;
  final List<PrinterItem> printers;
  final List<Map<String, dynamic>> logs;
  final bool isOffline;

  PrinterOverviewData copyWith({
    PrinterDashboardData? dashboard,
    List<PrinterBranchItem>? branches,
    List<PrinterItem>? printers,
    List<Map<String, dynamic>>? logs,
    bool? isOffline,
  }) {
    return PrinterOverviewData(
      dashboard: dashboard ?? this.dashboard,
      branches: branches ?? this.branches,
      printers: printers ?? this.printers,
      logs: logs ?? this.logs,
      isOffline: isOffline ?? this.isOffline,
    );
  }

  static const empty = PrinterOverviewData(
    dashboard: PrinterDashboardData.empty,
    branches: <PrinterBranchItem>[],
    printers: <PrinterItem>[],
    logs: <Map<String, dynamic>>[],
    isOffline: false,
  );
}

class PrinterHistoryEntry {
  const PrinterHistoryEntry({
    required this.id,
    required this.snapshotAt,
    required this.counters,
    required this.lifetimeCounters,
    required this.tonerLevels,
    required this.maintenance,
    required this.status,
  });

  final String id;
  final DateTime? snapshotAt;
  final Map<String, num> counters;
  final Map<String, num> lifetimeCounters;
  final Map<String, dynamic> tonerLevels;
  final Map<String, dynamic> maintenance;
  final String status;

  factory PrinterHistoryEntry.fromJson(Map<String, dynamic> json) {
    return PrinterHistoryEntry(
      id: json['id']?.toString() ?? '',
      snapshotAt: DateTime.tryParse(json['snapshotAt']?.toString() ?? ''),
      counters: _numMap(json['counters']),
      lifetimeCounters: _numMap(json['lifetimeCounters']),
      tonerLevels: _dynamicMap(json['tonerLevels']),
      maintenance: _dynamicMap(json['maintenance']),
      status: json['status']?.toString() ?? 'offline',
    );
  }
}

class PrinterDetailsData {
  const PrinterDetailsData({required this.printer, required this.history});

  final PrinterItem printer;
  final List<PrinterHistoryEntry> history;

  factory PrinterDetailsData.fromJson(Map<String, dynamic> json) {
    return PrinterDetailsData(
      printer: PrinterItem.fromJson(_dynamicMap(json['printer'])),
      history: _list(json['history'])
          .map((entry) => PrinterHistoryEntry.fromJson(_dynamicMap(entry)))
          .toList(),
    );
  }
}

Map<String, dynamic> _dynamicMap(Object? raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

Map<String, num> _numMap(Object? raw) {
  return _dynamicMap(raw).map((key, value) {
    final parsed = value is num
        ? value
        : num.tryParse(value?.toString() ?? '') ?? 0;
    return MapEntry(key, parsed);
  });
}

List<dynamic> _list(Object? raw) => raw is List ? raw : const <dynamic>[];
