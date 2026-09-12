class ItAsset {
  const ItAsset({
    required this.id,
    required this.assetCode,
    required this.category,
    required this.assetType,
    required this.brand,
    required this.model,
    required this.serialNumber,
    required this.status,
    required this.condition,
    required this.branchName,
    required this.location,
    required this.assignedTo,
    required this.vendor,
    required this.invoiceNumber,
    required this.purchaseDate,
    required this.warrantyEndDate,
    required this.notes,
    required this.timeline,
    required this.updatedAt,
  });

  final String id;
  final String assetCode;
  final String category;
  final String assetType;
  final String brand;
  final String model;
  final String? serialNumber;
  final String status;
  final String condition;
  final String branchName;
  final String location;
  final String assignedTo;
  final String vendor;
  final String invoiceNumber;
  final DateTime? purchaseDate;
  final DateTime? warrantyEndDate;
  final String notes;
  final List<ItTimelineEntry> timeline;
  final DateTime? updatedAt;

  factory ItAsset.fromJson(Map<String, dynamic> json) => ItAsset(
    id: (json['_id'] ?? json['id']).toString(),
    assetCode: json['assetCode']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    assetType: json['assetType']?.toString() ?? '',
    brand: json['brand']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    serialNumber: _optionalText(json['serialNumber']),
    status: json['status']?.toString() ?? 'available',
    condition: json['condition']?.toString() ?? 'good',
    branchName: json['branchName']?.toString() ?? '',
    location: json['location']?.toString() ?? '',
    assignedTo: json['assignedTo']?.toString() ?? '',
    vendor: json['vendor']?.toString() ?? '',
    invoiceNumber: json['invoiceNumber']?.toString() ?? '',
    purchaseDate: DateTime.tryParse(json['purchaseDate']?.toString() ?? ''),
    warrantyEndDate: DateTime.tryParse(
      json['warrantyEndDate']?.toString() ?? '',
    ),
    notes: json['notes']?.toString() ?? '',
    timeline: (json['timeline'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ItTimelineEntry.fromJson)
        .toList(),
    updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
  );
}

class ItTimelineEntry {
  const ItTimelineEntry({
    required this.action,
    required this.details,
    required this.documentNumber,
    required this.performedByName,
    required this.createdAt,
  });

  final String action;
  final String details;
  final String? documentNumber;
  final String performedByName;
  final DateTime? createdAt;

  factory ItTimelineEntry.fromJson(Map<String, dynamic> json) =>
      ItTimelineEntry(
        action: json['action']?.toString() ?? '',
        details: json['details']?.toString() ?? '',
        documentNumber: _optionalText(json['documentNumber']),
        performedByName: json['performedByName']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );
}

class ItSparePart {
  const ItSparePart({
    required this.id,
    required this.partCode,
    required this.name,
    required this.category,
    required this.brand,
    required this.model,
    required this.unit,
    required this.quantityAvailable,
    required this.quantityReserved,
    required this.damagedQuantity,
    required this.minimumQuantity,
    required this.criticalQuantity,
    required this.preferredQuantity,
    required this.location,
    required this.hasSerialNumbers,
    required this.notes,
  });

  final String id;
  final String partCode;
  final String name;
  final String category;
  final String brand;
  final String model;
  final String unit;
  final int quantityAvailable;
  final int quantityReserved;
  final int damagedQuantity;
  final int minimumQuantity;
  final int criticalQuantity;
  final int preferredQuantity;
  final String location;
  final bool hasSerialNumbers;
  final String notes;

  int get usableQuantity => quantityAvailable - quantityReserved;
  bool get isLowStock => usableQuantity <= minimumQuantity;

  factory ItSparePart.fromJson(Map<String, dynamic> json) => ItSparePart(
    id: (json['_id'] ?? json['id']).toString(),
    partCode: json['partCode']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    brand: json['brand']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    unit: json['unit']?.toString() ?? 'قطعة',
    quantityAvailable: _asInt(json['quantityAvailable']),
    quantityReserved: _asInt(json['quantityReserved']),
    damagedQuantity: _asInt(json['damagedQuantity']),
    minimumQuantity: _asInt(json['minimumQuantity']),
    criticalQuantity: _asInt(json['criticalQuantity']),
    preferredQuantity: _asInt(json['preferredQuantity']),
    location: json['location']?.toString() ?? '',
    hasSerialNumbers: json['hasSerialNumbers'] == true,
    notes: json['notes']?.toString() ?? '',
  );
}

class ItOperation {
  const ItOperation({
    required this.id,
    required this.documentNumber,
    required this.operationType,
    required this.title,
    required this.status,
    required this.details,
    required this.solution,
    required this.auditNote,
    required this.auditReference,
    required this.fromLocation,
    required this.toLocation,
    required this.assignedTo,
    required this.quantity,
    required this.createdByName,
    required this.asset,
    required this.sparePart,
    required this.createdAt,
    required this.rootCause,
    required this.priority,
    required this.dueAt,
    required this.expectedReturnDate,
    required this.signedByName,
    required this.metadata,
  });

  final String id;
  final String documentNumber;
  final String operationType;
  final String title;
  final String status;
  final String details;
  final String solution;
  final String auditNote;
  final String auditReference;
  final String fromLocation;
  final String toLocation;
  final String assignedTo;
  final int quantity;
  final String createdByName;
  final ItAsset? asset;
  final ItSparePart? sparePart;
  final DateTime? createdAt;
  final String rootCause;
  final String priority;
  final DateTime? dueAt;
  final DateTime? expectedReturnDate;
  final String signedByName;
  final Map<String, dynamic> metadata;

  factory ItOperation.fromJson(Map<String, dynamic> json) => ItOperation(
    id: (json['_id'] ?? json['id']).toString(),
    documentNumber: json['documentNumber']?.toString() ?? '',
    operationType: json['operationType']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    details: json['details']?.toString() ?? '',
    solution: json['solution']?.toString() ?? '',
    auditNote: json['auditNote']?.toString() ?? '',
    auditReference: json['auditReference']?.toString() ?? '',
    fromLocation: json['fromLocation']?.toString() ?? '',
    toLocation: json['toLocation']?.toString() ?? '',
    assignedTo: json['assignedTo']?.toString() ?? '',
    quantity: _asInt(json['quantity']),
    createdByName: json['createdByName']?.toString() ?? '',
    asset: json['assetId'] is Map<String, dynamic>
        ? ItAsset.fromJson(json['assetId'] as Map<String, dynamic>)
        : null,
    sparePart: json['sparePartId'] is Map<String, dynamic>
        ? ItSparePart.fromJson(json['sparePartId'] as Map<String, dynamic>)
        : null,
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    rootCause: json['rootCause']?.toString() ?? '',
    priority: json['priority']?.toString() ?? 'medium',
    dueAt: DateTime.tryParse(json['dueAt']?.toString() ?? ''),
    expectedReturnDate: DateTime.tryParse(
      json['expectedReturnDate']?.toString() ?? '',
    ),
    signedByName: json['signedByName']?.toString() ?? '',
    metadata: json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : const {},
  );
}

class ItControlRecord {
  const ItControlRecord({
    required this.id,
    required this.recordType,
    required this.recordNumber,
    required this.title,
    required this.status,
    required this.branchName,
    required this.location,
    required this.assignedTo,
    required this.reason,
    required this.notes,
    required this.data,
    required this.signatures,
    required this.locked,
    required this.createdByName,
    required this.createdAt,
    required this.asset,
    required this.sparePart,
  });

  final String id;
  final String recordType;
  final String recordNumber;
  final String title;
  final String status;
  final String branchName;
  final String location;
  final String assignedTo;
  final String reason;
  final String notes;
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> signatures;
  final bool locked;
  final String createdByName;
  final DateTime? createdAt;
  final ItAsset? asset;
  final ItSparePart? sparePart;

  factory ItControlRecord.fromJson(Map<String, dynamic> json) =>
      ItControlRecord(
        id: (json['_id'] ?? json['id']).toString(),
        recordType: json['recordType']?.toString() ?? '',
        recordNumber: json['recordNumber']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        branchName: json['branchName']?.toString() ?? '',
        location: json['location']?.toString() ?? '',
        assignedTo: json['assignedTo']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        data: json['data'] is Map
            ? Map<String, dynamic>.from(json['data'] as Map)
            : const {},
        signatures: (json['signatures'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(),
        locked: json['locked'] == true,
        createdByName: json['createdByName']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
        asset: json['assetId'] is Map<String, dynamic>
            ? ItAsset.fromJson(json['assetId'] as Map<String, dynamic>)
            : null,
        sparePart: json['sparePartId'] is Map<String, dynamic>
            ? ItSparePart.fromJson(json['sparePartId'] as Map<String, dynamic>)
            : null,
      );
}

class ItAttachment {
  const ItAttachment({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.size,
    required this.uploadedByName,
    required this.createdAt,
  });

  final String id;
  final String originalName;
  final String mimeType;
  final int size;
  final String uploadedByName;
  final DateTime? createdAt;

  factory ItAttachment.fromJson(Map<String, dynamic> json) => ItAttachment(
    id: (json['_id'] ?? json['id']).toString(),
    originalName: json['originalName']?.toString() ?? '',
    mimeType: json['mimeType']?.toString() ?? '',
    size: _asInt(json['size']),
    uploadedByName: json['uploadedByName']?.toString() ?? '',
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
  );
}

class ItAuditEntry {
  const ItAuditEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.documentNumber,
    required this.summary,
    required this.actorName,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String entityType;
  final String? documentNumber;
  final String summary;
  final String actorName;
  final DateTime? createdAt;

  factory ItAuditEntry.fromJson(Map<String, dynamic> json) => ItAuditEntry(
    id: (json['_id'] ?? json['id']).toString(),
    action: json['action']?.toString() ?? '',
    entityType: json['entityType']?.toString() ?? '',
    documentNumber: _optionalText(json['documentNumber']),
    summary: json['summary']?.toString() ?? '',
    actorName: json['actorName']?.toString() ?? '',
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
  );
}

class ItAssetsOverview {
  const ItAssetsOverview({
    required this.totalAssets,
    required this.availableAssets,
    required this.assignedAssets,
    required this.maintenanceAssets,
    required this.damagedAssets,
    required this.totalSpareParts,
    required this.lowStock,
    required this.pendingOperations,
    required this.openMaintenance,
    required this.recentOperations,
  });

  final int totalAssets;
  final int availableAssets;
  final int assignedAssets;
  final int maintenanceAssets;
  final int damagedAssets;
  final int totalSpareParts;
  final int lowStock;
  final int pendingOperations;
  final int openMaintenance;
  final List<ItOperation> recentOperations;

  factory ItAssetsOverview.fromJson(Map<String, dynamic> json) =>
      ItAssetsOverview(
        totalAssets: _asInt(json['totalAssets']),
        availableAssets: _asInt(json['availableAssets']),
        assignedAssets: _asInt(json['assignedAssets']),
        maintenanceAssets: _asInt(json['maintenanceAssets']),
        damagedAssets: _asInt(json['damagedAssets']),
        totalSpareParts: _asInt(json['totalSpareParts']),
        lowStock: _asInt(json['lowStock']),
        pendingOperations: _asInt(json['pendingOperations']),
        openMaintenance: _asInt(json['openMaintenance']),
        recentOperations:
            (json['recentOperations'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(ItOperation.fromJson)
                .toList(),
      );
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
