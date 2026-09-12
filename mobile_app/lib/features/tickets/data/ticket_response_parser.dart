import '../models/ticket_models.dart';

Map<String, dynamic> asStringKeyedMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const {};
}

Map<String, dynamic> mergeResponseBody(Map<String, dynamic> body) {
  final merged = <String, dynamic>{};
  for (final entry in body.entries) {
    if (entry.key == 'success' || entry.key == 'error' || entry.key == 'data') {
      continue;
    }
    merged[entry.key] = entry.value;
  }
  merged.addAll(asStringKeyedMap(body['data']));
  return merged;
}

Map<String, dynamic> readMeta(Map<String, dynamic> body) {
  return asStringKeyedMap(body['meta']);
}

bool looksLikeTicketMap(Map<String, dynamic> map) {
  if (map.isEmpty) {
    return false;
  }
  final id = map['id']?.toString() ?? map['_id']?.toString() ?? '';
  final title = map['title']?.toString() ?? '';
  final ticketNumber = map['ticketNumber']?.toString() ?? '';
  return id.isNotEmpty || title.isNotEmpty || ticketNumber.isNotEmpty;
}

Map<String, dynamic> normalizeTicketMap(Map<String, dynamic> raw) {
  final map = Map<String, dynamic>.from(raw);
  if ((map['id']?.toString() ?? '').isEmpty && map['_id'] != null) {
    map['id'] = map['_id']?.toString() ?? '';
  }
  return map;
}

Map<String, dynamic> readTicketMap(Map<String, dynamic> body) {
  final merged = mergeResponseBody(body);
  final nestedTicket = normalizeTicketMap(asStringKeyedMap(merged['ticket']));
  if (looksLikeTicketMap(nestedTicket)) {
    return nestedTicket;
  }
  if (looksLikeTicketMap(merged)) {
    return normalizeTicketMap(merged);
  }
  final rootTicket = normalizeTicketMap(asStringKeyedMap(body['ticket']));
  if (looksLikeTicketMap(rootTicket)) {
    return rootTicket;
  }
  return const {};
}

List<Map<String, dynamic>> readTicketsList(Map<String, dynamic> body) {
  final merged = mergeResponseBody(body);
  final raw = merged['tickets'];
  if (raw is List) {
    return _mapsFromList(raw);
  }
  if (body['data'] is List) {
    return _mapsFromList(body['data'] as List);
  }
  return const [];
}

bool looksLikeUpdateMap(Map<String, dynamic> map) {
  if (map.isEmpty) {
    return false;
  }
  final id = map['id']?.toString() ?? map['_id']?.toString() ?? '';
  final kind = map['kind']?.toString() ?? '';
  final message = map['message']?.toString() ?? '';
  return id.isNotEmpty || kind.isNotEmpty || message.isNotEmpty;
}

Map<String, dynamic> normalizeUpdateMap(Map<String, dynamic> raw) {
  final map = Map<String, dynamic>.from(raw);
  if ((map['id']?.toString() ?? '').isEmpty && map['_id'] != null) {
    map['id'] = map['_id']?.toString() ?? '';
  }

  final createdBy = asStringKeyedMap(map['createdBy']);
  final rootName = map['createdByName']?.toString().trim() ?? '';
  if ((createdBy['fullName']?.toString().trim() ?? '').isEmpty &&
      rootName.isNotEmpty) {
    createdBy['fullName'] = rootName;
    map['createdBy'] = createdBy;
  }

  return map;
}

List<Map<String, dynamic>> readUpdatesList(Map<String, dynamic> body) {
  final merged = mergeResponseBody(body);
  final raw = merged['updates'] ?? body['updates'];
  if (raw is! List) {
    return const [];
  }
  return raw
      .map(asStringKeyedMap)
      .where(looksLikeUpdateMap)
      .map(normalizeUpdateMap)
      .toList();
}

List<Map<String, dynamic>> _mapsFromList(List<dynamic> raw) {
  return raw
      .map(asStringKeyedMap)
      .where(looksLikeTicketMap)
      .map(normalizeTicketMap)
      .toList();
}

Map<String, dynamic> readObject(Map<String, dynamic> body, String key) {
  final merged = mergeResponseBody(body);
  return asStringKeyedMap(merged[key] ?? body[key]);
}

List<Map<String, dynamic>> readObjectList(
  Map<String, dynamic> body,
  String key,
) {
  if (key == 'tickets') {
    return readTicketsList(body);
  }
  if (key == 'updates') {
    return readUpdatesList(body);
  }
  final merged = mergeResponseBody(body);
  final raw = merged[key] ?? body[key];
  if (raw is! List) {
    return const [];
  }
  return raw.map(asStringKeyedMap).where((entry) => entry.isNotEmpty).toList();
}

TicketItem parseTicketItem(Map<String, dynamic> body) {
  return TicketItem.fromJson(readTicketMap(body));
}
