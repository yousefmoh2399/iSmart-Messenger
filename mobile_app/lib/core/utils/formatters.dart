import 'dart:math';
import 'package:intl/intl.dart';

import 'date_time_utils.dart';

String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB'];
  final index = min((log(bytes) / log(1024)).floor(), suffixes.length - 1);
  final value = bytes / pow(1024, index);
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${suffixes[index]}';
}

String formatDate(DateTime dateTime) {
  return formatEgyptDateTime(dateTime);
}

String formatEgyptTime(DateTime dateTime) {
  final local = toAppLocalTime(dateTime);
  final hour = DateFormat('h', 'ar').format(local);
  final minute = DateFormat('mm', 'ar').format(local);
  final period = local.hour >= 12 ? 'مساءً' : 'صباحًا';
  return '$hour:$minute $period';
}

String formatEgyptDate(DateTime dateTime, {String pattern = 'yyyy/MM/dd'}) {
  return DateFormat(pattern, 'ar').format(toAppLocalTime(dateTime));
}

String formatEgyptDateTime(
  DateTime dateTime, {
  String datePattern = 'yyyy/MM/dd',
  String separator = ' - ',
}) {
  return '${formatEgyptDate(dateTime, pattern: datePattern)}$separator${formatEgyptTime(dateTime)}';
}

String _sanitizeOwnerLabel(String? ownerName) {
  final normalized = (ownerName ?? '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^0-9A-Za-z_\-\u0600-\u06FF]'), '');
  if (normalized.isEmpty) {
    return 'scan';
  }
  return normalized.length > 32 ? normalized.substring(0, 32) : normalized;
}

String defaultPdfName({DateTime? dateTime, String? ownerName}) {
  final now = dateTime ?? DateTime.now();
  final owner = _sanitizeOwnerLabel(ownerName);
  final stamp = DateFormat('yyyy_MM_dd_HH_mm_ss', 'en').format(now);
  return '${owner}_$stamp';
}

String sanitizePdfName(String input) {
  final clean = input
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(' ', '_');
  if (clean.isEmpty) return '${defaultPdfName()}.pdf';
  return clean.toLowerCase().endsWith('.pdf') ? clean : '$clean.pdf';
}
