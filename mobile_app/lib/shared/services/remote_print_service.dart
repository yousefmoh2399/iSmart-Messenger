import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/chat/data/chat_socket_service.dart';

const int kMaxInlinePrintBytes = 20 * 1024 * 1024;

class RemotePrintCatalog {
  const RemotePrintCatalog({
    required this.printers,
    required this.defaultPrinter,
    required this.hasDesktop,
  });

  final List<String> printers;
  final String? defaultPrinter;
  final bool hasDesktop;
}

class RemotePrintRequestResult {
  const RemotePrintRequestResult({
    required this.success,
    required this.message,
    required this.jobId,
  });

  final bool success;
  final String message;
  final String? jobId;
}

class RemotePrintService {
  const RemotePrintService(this._socket, this._authRepository);

  final ChatSocketService _socket;
  final AuthRepository _authRepository;

  Future<RemotePrintCatalog> fetchCatalog() async {
    final response = await _socket.emitWithAck('printers:get', {});
    final data = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'] as Map)
        : const <String, dynamic>{};
    final printers = (data['printers'] as List<dynamic>? ?? const <dynamic>[])
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();

    final initial = RemotePrintCatalog(
      printers: printers,
      defaultPrinter: data['defaultPrinter']?.toString(),
      hasDesktop: data['hasDesktop'] == true,
    );
    if (!initial.hasDesktop || initial.printers.isNotEmpty) {
      return initial;
    }

    try {
      final event = await _socket.events
          .firstWhere((event) => event.type == 'printers_catalog_updated')
          .timeout(const Duration(seconds: 8));
      final payload = event.payload;
      final refreshedPrinters =
          (payload['printers'] as List<dynamic>? ?? const <dynamic>[])
              .map((entry) => entry.toString().trim())
              .where((entry) => entry.isNotEmpty)
              .toList();
      if (refreshedPrinters.isNotEmpty) {
        return RemotePrintCatalog(
          printers: refreshedPrinters,
          defaultPrinter: payload['defaultPrinter']?.toString(),
          hasDesktop: true,
        );
      }
    } catch (_) {}

    return initial;
  }

  Future<RemotePrintRequestResult> requestPrintFromDownloadUrl({
    required String downloadUrl,
    required String fileName,
    String? mimeType,
    String? preferredPrinterName,
    String source = 'chat',
    String? clientRequestId,
  }) async {
    final token = await _authRepository.getValidToken();
    final effectiveClientRequestId = clientRequestId ?? const Uuid().v4();
    final response = await _socket.emitWithAck('print_request', {
      'downloadUrl': downloadUrl,
      'fileName': fileName,
      'mimeType': mimeType,
      'preferredPrinterName': preferredPrinterName,
      'source': source,
      'clientRequestId': effectiveClientRequestId,
      if (token != null && token.trim().isNotEmpty)
        'requestAuthToken': token.trim(),
    });
    final success = response['ok'] == true && response['success'] == true;
    final data = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'] as Map)
        : const <String, dynamic>{};
    final message =
        response['error']?.toString() ??
        (success
            ? 'تم إرسال طلب الطباعة إلى تطبيق الكمبيوتر.'
            : 'تعذر إرسال طلب الطباعة.');
    return RemotePrintRequestResult(
      success: success,
      message: message,
      jobId: data['jobId']?.toString(),
    );
  }

  Future<RemotePrintRequestResult> requestPrintFromLocalFile({
    required String filePath,
    String? fileName,
    String? mimeType,
    String? preferredPrinterName,
    String source = 'mobile_local_file',
    String? clientRequestId,
  }) async {
    final file = File(filePath);
    final exists = await file.exists();
    if (!exists) {
      return const RemotePrintRequestResult(
        success: false,
        message: 'الملف غير موجود على الجهاز.',
        jobId: null,
      );
    }

    final size = await file.length();
    if (size <= 0) {
      return const RemotePrintRequestResult(
        success: false,
        message: 'الملف فارغ ولا يمكن طباعته.',
        jobId: null,
      );
    }
    if (size > kMaxInlinePrintBytes) {
      return const RemotePrintRequestResult(
        success: false,
        message: 'حجم الملف كبير. الحد الأقصى للطباعة المباشرة هو 20 ميجا.',
        jobId: null,
      );
    }

    final bytes = await file.readAsBytes();
    final effectiveClientRequestId = clientRequestId ?? const Uuid().v4();
    final response = await _socket.emitWithAck('print_request', {
      'inlineFileBase64': base64Encode(bytes),
      'fileName': fileName ?? file.uri.pathSegments.last,
      'mimeType': mimeType,
      'preferredPrinterName': preferredPrinterName,
      'source': source,
      'clientRequestId': effectiveClientRequestId,
    });
    final success = response['ok'] == true && response['success'] == true;
    final data = response['data'] is Map
        ? Map<String, dynamic>.from(response['data'] as Map)
        : const <String, dynamic>{};
    final message =
        response['error']?.toString() ??
        (success
            ? 'تم إرسال طلب الطباعة إلى تطبيق الكمبيوتر.'
            : 'تعذر إرسال طلب الطباعة.');
    return RemotePrintRequestResult(
      success: success,
      message: message,
      jobId: data['jobId']?.toString(),
    );
  }
}
