import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

/// امتدادات ممنوعة اختياريًا (فارغة = أي نوع ملف ضمن حجم السيرفر).
const Set<String> kChatBlockedAttachmentExtensions = <String>{};

const String kChatBlockedAttachmentUserMessage =
    'لا يُسمح بهذا النوع من الملفات في الشات.';

bool isChatAttachmentExtensionBlocked(String filePath) {
  final ext = p.extension(filePath).toLowerCase();
  return kChatBlockedAttachmentExtensions.contains(ext);
}

String messageFromChatDioError(Object error) {
  if (error is! DioException) {
    return 'تعذر إرسال الملف.';
  }
  final data = error.response?.data;
  if (data is Map) {
    final m = data['message'] ?? data['error'];
    if (m is String && m.trim().isNotEmpty) {
      return m.trim();
    }
  }
  final msg = error.message?.trim();
  if (msg != null && msg.isNotEmpty) {
    return msg;
  }
  return 'تعذر إرسال الملف.';
}
