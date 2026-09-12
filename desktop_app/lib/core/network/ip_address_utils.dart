String normalizeIpAddress(String? raw) {
  var value = (raw ?? '').trim();
  if (value.isEmpty) {
    return '';
  }

  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && (uri.host).trim().isNotEmpty) {
    value = uri.host.trim();
  }

  if (value.startsWith('[') && value.endsWith(']')) {
    value = value.substring(1, value.length - 1).trim();
  }

  final zoneIndex = value.indexOf('%');
  if (zoneIndex >= 0) {
    value = value.substring(0, zoneIndex).trim();
  }

  if (value.startsWith('::ffff:')) {
    final mapped = value.substring('::ffff:'.length).trim();
    if (mapped.isNotEmpty) {
      return mapped;
    }
  }

  if (value.startsWith('=ffff:')) {
    final mapped = value.substring('=ffff:'.length).trim();
    if (mapped.isNotEmpty) {
      value = mapped;
    }
  }

  final ipv4Match = RegExp(r'(?:\d{1,3}\.){3}\d{1,3}').firstMatch(value);
  if (ipv4Match != null) {
    return ipv4Match.group(0)!.trim();
  }

  final hostPortMatch = RegExp(
    r'^((?:\d{1,3}\.){3}\d{1,3}):\d+$',
  ).firstMatch(value);
  if (hostPortMatch != null) {
    return hostPortMatch.group(1)!.trim();
  }

  return value;
}
