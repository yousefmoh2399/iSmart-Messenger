import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const appTimeZoneName = 'Africa/Cairo';

bool _timeZonesInitialized = false;
tz.Location? _appTimeZone;

tz.Location get appTimeZone {
  if (!_timeZonesInitialized) {
    tzdata.initializeTimeZones();
    _timeZonesInitialized = true;
  }
  return _appTimeZone ??= tz.getLocation(appTimeZoneName);
}

DateTime toAppLocalTime(DateTime value) {
  return tz.TZDateTime.from(value.toUtc(), appTimeZone);
}

DateTime? parseBackendDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return toAppLocalTime(value);
  }

  final raw = value.toString().trim();
  if (raw.isEmpty) {
    return null;
  }

  final normalized = _hasExplicitTimeZone(raw) ? raw : '${raw}Z';
  final parsed = DateTime.tryParse(normalized) ?? DateTime.tryParse(raw);
  if (parsed == null) {
    return null;
  }
  return toAppLocalTime(parsed);
}

bool _hasExplicitTimeZone(String value) {
  return RegExp(
    r'(?:Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(value);
}
