class MobileItAsset {
  const MobileItAsset({
    required this.id,
    required this.assetCode,
    required this.assetType,
    required this.brand,
    required this.model,
    required this.serialNumber,
    required this.status,
    required this.condition,
    required this.branchName,
    required this.location,
    required this.assignedTo,
    required this.notes,
    required this.timeline,
  });

  final String id;
  final String assetCode;
  final String assetType;
  final String brand;
  final String model;
  final String? serialNumber;
  final String status;
  final String condition;
  final String branchName;
  final String location;
  final String assignedTo;
  final String notes;
  final List<MobileItTimelineEntry> timeline;

  factory MobileItAsset.fromJson(Map<String, dynamic> json) => MobileItAsset(
    id: (json['_id'] ?? json['id']).toString(),
    assetCode: json['assetCode']?.toString() ?? '',
    assetType: json['assetType']?.toString() ?? '',
    brand: json['brand']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    serialNumber: _optional(json['serialNumber']),
    status: json['status']?.toString() ?? '',
    condition: json['condition']?.toString() ?? '',
    branchName: json['branchName']?.toString() ?? '',
    location: json['location']?.toString() ?? '',
    assignedTo: json['assignedTo']?.toString() ?? '',
    notes: json['notes']?.toString() ?? '',
    timeline: (json['timeline'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MobileItTimelineEntry.fromJson)
        .toList(),
  );
}

class MobileItTimelineEntry {
  const MobileItTimelineEntry({
    required this.details,
    required this.documentNumber,
    required this.performedByName,
    required this.createdAt,
  });

  final String details;
  final String? documentNumber;
  final String performedByName;
  final DateTime? createdAt;

  factory MobileItTimelineEntry.fromJson(Map<String, dynamic> json) =>
      MobileItTimelineEntry(
        details: json['details']?.toString() ?? '',
        documentNumber: _optional(json['documentNumber']),
        performedByName: json['performedByName']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );
}

class MobileSparePart {
  const MobileSparePart({
    required this.id,
    required this.partCode,
    required this.name,
    required this.category,
    required this.quantityAvailable,
    required this.quantityReserved,
    required this.damagedQuantity,
    required this.minimumQuantity,
    required this.location,
  });

  final String id;
  final String partCode;
  final String name;
  final String category;
  final int quantityAvailable;
  final int quantityReserved;
  final int damagedQuantity;
  final int minimumQuantity;
  final String location;

  int get usableQuantity => quantityAvailable - quantityReserved;
  bool get isLowStock => usableQuantity <= minimumQuantity;

  factory MobileSparePart.fromJson(Map<String, dynamic> json) =>
      MobileSparePart(
        id: (json['_id'] ?? json['id']).toString(),
        partCode: json['partCode']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        quantityAvailable: (json['quantityAvailable'] as num?)?.toInt() ?? 0,
        quantityReserved: (json['quantityReserved'] as num?)?.toInt() ?? 0,
        damagedQuantity: (json['damagedQuantity'] as num?)?.toInt() ?? 0,
        minimumQuantity: (json['minimumQuantity'] as num?)?.toInt() ?? 0,
        location: json['location']?.toString() ?? '',
      );
}

class MobileInventorySession {
  const MobileInventorySession({
    required this.id,
    required this.recordNumber,
    required this.title,
    required this.branchName,
    required this.location,
    required this.expectedCount,
    required this.scannedCount,
  });

  final String id;
  final String recordNumber;
  final String title;
  final String branchName;
  final String location;
  final int expectedCount;
  final int scannedCount;

  factory MobileInventorySession.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map
        ? Map<String, dynamic>.from(json['data'])
        : const <String, dynamic>{};
    return MobileInventorySession(
      id: (json['_id'] ?? json['id']).toString(),
      recordNumber: json['recordNumber']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      branchName: json['branchName']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      expectedCount: (data['expectedAssetIds'] as List?)?.length ?? 0,
      scannedCount: (data['scannedAssetIds'] as List?)?.length ?? 0,
    );
  }
}

String? _optional(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
