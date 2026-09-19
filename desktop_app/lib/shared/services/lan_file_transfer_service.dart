import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:desktop_app/shared/services/web_platform_bridge_stub.dart' as web_bridge;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/network/ip_address_utils.dart';
import 'local_media_storage_service.dart';

const int kLanFileTransferPort = 27861;

class LanIncomingTransferRequest {
  LanIncomingTransferRequest._({
    required this.requestId,
    required this.senderName,
    required this.senderIp,
    required this.fileName,
    required this.fileSizeBytes,
    required this.mimeType,
    required Future<void> Function(String? saveDirectoryPath) onAccept,
    required Future<void> Function() onReject,
  }) : _onAccept = onAccept,
       _onReject = onReject;

  final String requestId;
  final String senderName;
  final String senderIp;
  final String fileName;
  final int fileSizeBytes;
  final String? mimeType;
  final Future<void> Function(String? saveDirectoryPath) _onAccept;
  final Future<void> Function() _onReject;

  Future<void> accept({String? saveDirectoryPath}) =>
      _onAccept(saveDirectoryPath);

  Future<void> reject() => _onReject();
}

class LanTransferProgressEvent {
  const LanTransferProgressEvent({
    required this.direction,
    required this.stage,
    required this.progress,
    required this.fileName,
    this.message,
    this.peerIp,
    this.savedPath,
  });

  final String direction;
  final String stage;
  final double progress;
  final String fileName;
  final String? message;
  final String? peerIp;
  final String? savedPath;
}

class LanSendFileResult {
  const LanSendFileResult({
    required this.success,
    required this.message,
    this.savedPath,
  });

  final bool success;
  final String message;
  final String? savedPath;
}

class LanPeerProbeResult {
  const LanPeerProbeResult({
    required this.success,
    required this.message,
    required this.peerIp,
    this.peerIps = const <String>[],
  });

  final bool success;
  final String message;
  final String peerIp;
  final List<String> peerIps;
}

class LanDiscoveredPeer {
  const LanDiscoveredPeer({required this.ip, this.peerIps = const <String>[]});

  final String ip;
  final List<String> peerIps;
}

class LanFileTransferService {
  final StreamController<LanIncomingTransferRequest> _incomingController =
      StreamController<LanIncomingTransferRequest>.broadcast();
  final StreamController<LanTransferProgressEvent> _progressController =
      StreamController<LanTransferProgressEvent>.broadcast();
  final Map<String, _PendingLanTransfer> _pendingTransfers =
      <String, _PendingLanTransfer>{};
  final Dio _dio = Dio();
  HttpServer? _server;
  Future<void>? _startFuture;
  List<String> _localIpv4s = const <String>[];

  Stream<LanIncomingTransferRequest> get incomingRequests =>
      _incomingController.stream;
  Stream<LanTransferProgressEvent> get progressEvents =>
      _progressController.stream;
  List<String> get localIpv4s => List<String>.unmodifiable(_localIpv4s);
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (kIsWeb) {
      _localIpv4s = const <String>[];
      return;
    }
    if (_server != null) {
      await refreshLocalIpv4s();
      return;
    }
    final inFlight = _startFuture;
    if (inFlight != null) {
      await inFlight;
      await refreshLocalIpv4s();
      return;
    }
    _startFuture = _startServer();
    try {
      await _startFuture;
    } finally {
      _startFuture = null;
    }
  }

  Future<void> _startServer() async {
    if (_server != null) {
      return;
    }
    _localIpv4s = await _resolveLocalIpv4s();
    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        kLanFileTransferPort,
        shared: true,
      );
      _server = server;
      unawaited(server.forEach(_handleRequest));
    } on SocketException catch (error) {
      if (error.osError?.errorCode == 10048) {
        await refreshLocalIpv4s();
        return;
      }
      rethrow;
    }
  }

  Future<void> stop() async {
    final inFlight = _startFuture;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {}
    }
    final server = _server;
    _server = null;
    for (final pending in _pendingTransfers.values) {
      if (!pending.decision.isCompleted) {
        pending.decision.complete(const _LanDecision.rejected());
      }
      try {
        pending.outputFile?.deleteSync();
      } catch (_) {}
    }
    _pendingTransfers.clear();
    await server?.close(force: true);
  }

  Future<List<String>> refreshLocalIpv4s() async {
    if (kIsWeb) {
      _localIpv4s = const <String>[];
      return localIpv4s;
    }
    _localIpv4s = await _resolveLocalIpv4s();
    return localIpv4s;
  }

  Future<List<LanDiscoveredPeer>> discoverPeersOnLocalNetworks() async {
    if (kIsWeb) {
      return const <LanDiscoveredPeer>[];
    }
    final currentLocalIps = await refreshLocalIpv4s();
    final localSet = currentLocalIps
        .map(normalizeIpAddress)
        .where((entry) => entry.isNotEmpty)
        .toSet();
    final subnetKeys =
        currentLocalIps
            .map(_ipv4SubnetKey)
            .where((entry) => entry.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (subnetKeys.isEmpty) {
      return const <LanDiscoveredPeer>[];
    }

    final candidates = <String>[];
    for (final subnet in subnetKeys) {
      for (var host = 1; host <= 254; host += 1) {
        final candidate = '$subnet.$host';
        if (!localSet.contains(candidate)) {
          candidates.add(candidate);
        }
      }
    }

    const batchSize = 128;
    final discovered = <String, LanDiscoveredPeer>{};
    for (var index = 0; index < candidates.length; index += batchSize) {
      final batch = candidates.skip(index).take(batchSize).toList();
      final results = await Future.wait(
        batch.map(
          (candidate) => probeTargetIp(
            candidate,
            timeout: const Duration(milliseconds: 600),
          ),
        ),
      );
      for (final result in results) {
        if (!result.success) {
          continue;
        }
        final normalizedIp = normalizeIpAddress(result.peerIp);
        if (normalizedIp.isEmpty) {
          continue;
        }
        discovered[normalizedIp] = LanDiscoveredPeer(
          ip: normalizedIp,
          peerIps: result.peerIps,
        );
      }
    }

    return discovered.values.toList()..sort((a, b) => a.ip.compareTo(b.ip));
  }

  Future<LanPeerProbeResult> probeTargetIp(
    String targetIp, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final trimmedIp = normalizeIpAddress(targetIp);
    if (trimmedIp.isEmpty) {
      return const LanPeerProbeResult(
        success: false,
        message: 'عنوان IP مطلوب.',
        peerIp: '',
      );
    }

    try {
      if (kIsWeb) {
        final res = await web_bridge.probeLanPeer(trimmedIp);
        final success = res['success'] == true;
        final peerIps = (res['ips'] as List<dynamic>? ?? const <dynamic>[])
            .map((entry) => normalizeIpAddress(entry.toString()))
            .where((entry) => entry.trim().isNotEmpty)
            .toList();
        return LanPeerProbeResult(
          success: success,
          peerIp: trimmedIp,
          peerIps: peerIps,
          message: success
              ? 'تم الاتصال بالجهاز $trimmedIp بنجاح.'
              : 'الجهاز رد لكن خدمة النقل المحلي غير جاهزة.',
        );
      }

      final response = await _dio.getUri<Map<String, dynamic>>(
        _buildLanUri(trimmedIp, '/lan-transfer/info'),
        options: Options(
          connectTimeout: timeout,
          sendTimeout: kIsWeb ? null : timeout,
          receiveTimeout: timeout,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final data = response.data ?? const <String, dynamic>{};
      final success = data['success'] == true;
      final peerIps = (data['ips'] as List<dynamic>? ?? const <dynamic>[])
          .map((entry) => normalizeIpAddress(entry.toString()))
          .where((entry) => entry.trim().isNotEmpty)
          .toList();
      return LanPeerProbeResult(
        success: success,
        peerIp: trimmedIp,
        peerIps: peerIps,
        message: success
            ? 'تم الاتصال بالجهاز $trimmedIp بنجاح.'
            : 'الجهاز رد لكن خدمة النقل المحلي غير جاهزة.',
      );
    } on DioException catch (error) {
      return LanPeerProbeResult(
        success: false,
        peerIp: trimmedIp,
        message: error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'تعذر الاتصال بالجهاز $trimmedIp عبر الشبكة المحلية.',
      );
    } catch (error) {
      return LanPeerProbeResult(
        success: false,
        peerIp: trimmedIp,
        message: error.toString(),
      );
    }
  }

  Future<LanSendFileResult> sendFileToIp({
    required String targetIp,
    required String filePath,
    required String senderName,
    void Function(LanTransferProgressEvent event)? onProgress,
  }) async {
    final trimmedIp = normalizeIpAddress(targetIp);
    if (trimmedIp.isEmpty) {
      return const LanSendFileResult(
        success: false,
        message: 'عنوان IP مطلوب.',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return const LanSendFileResult(
        success: false,
        message: 'الملف غير موجود على هذا الجهاز.',
      );
    }

    final fileName = p.basename(filePath);
    final fileSize = await file.length();
    _emitProgress(
      LanTransferProgressEvent(
        direction: 'outgoing',
        stage: 'connecting',
        progress: 0.04,
        fileName: fileName,
        peerIp: trimmedIp,
        message: 'جارٍ الاتصال بالجهاز $trimmedIp...',
      ),
      onProgress,
    );

    try {
      final requestUri = Uri.parse(
        _buildLanUri(trimmedIp, '/lan-transfer/request').toString(),
      );
      final requestResponse = await _dio.postUri<Map<String, dynamic>>(
        requestUri,
        data: <String, dynamic>{
          'fileName': fileName,
          'fileSizeBytes': fileSize,
          'senderName': senderName.trim().isEmpty
              ? 'مستخدم'
              : senderName.trim(),
          'mimeType': _guessMimeType(fileName),
        },
        options: Options(
          contentType: Headers.jsonContentType,
          sendTimeout: kIsWeb ? null : const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 3),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final responseData = requestResponse.data ?? const <String, dynamic>{};
      final accepted = responseData['accepted'] == true;
      if (!accepted) {
        return LanSendFileResult(
          success: false,
          message:
              responseData['message']?.toString() ?? 'تم رفض استلام الملف.',
        );
      }

      final transferId = responseData['transferId']?.toString().trim() ?? '';
      if (transferId.isEmpty) {
        return const LanSendFileResult(
          success: false,
          message: 'الجهاز الآخر لم يرجع معرّف نقل صالح.',
        );
      }

      _emitProgress(
        LanTransferProgressEvent(
          direction: 'outgoing',
          stage: 'accepted',
          progress: 0.16,
          fileName: fileName,
          peerIp: trimmedIp,
          message: 'وافق الجهاز الآخر. جارٍ إرسال الملف...',
        ),
        onProgress,
      );

      final uploadUri = Uri.parse(
        _buildLanUri(trimmedIp, '/lan-transfer/upload/$transferId').toString(),
      );
      final stream = file.openRead();
      final response = await _dio.postUri<Map<String, dynamic>>(
        uploadUri,
        data: stream,
        onSendProgress: (sent, total) {
          final ratio = total <= 0
              ? 0.0
              : (sent / total).clamp(0, 1).toDouble();
          _emitProgress(
            LanTransferProgressEvent(
              direction: 'outgoing',
              stage: 'uploading',
              progress: 0.16 + (ratio * 0.84),
              fileName: fileName,
              peerIp: trimmedIp,
              message: 'جارٍ إرسال الملف ${(ratio * 100).toStringAsFixed(0)}%',
            ),
            onProgress,
          );
        },
        options: Options(
          headers: <String, dynamic>{
            HttpHeaders.contentLengthHeader: fileSize,
            HttpHeaders.contentTypeHeader: 'application/octet-stream',
          },
          sendTimeout: kIsWeb ? null : _transferTimeoutForBytes(fileSize),
          receiveTimeout: const Duration(minutes: 2),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final payload = response.data ?? const <String, dynamic>{};
      final success = payload['success'] == true;
      final message =
          payload['message']?.toString() ??
          (success
              ? 'تم إرسال الملف بنجاح عبر الشبكة المحلية.'
              : 'فشل إرسال الملف عبر الشبكة المحلية.');
      _emitProgress(
        LanTransferProgressEvent(
          direction: 'outgoing',
          stage: success ? 'completed' : 'failed',
          progress: 1,
          fileName: fileName,
          peerIp: trimmedIp,
          message: message,
          savedPath: payload['savedPath']?.toString(),
        ),
        onProgress,
      );
      return LanSendFileResult(
        success: success,
        message: message,
        savedPath: payload['savedPath']?.toString(),
      );
    } on DioException catch (error) {
      final message = error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'تعذر الاتصال بالجهاز الآخر عبر الشبكة المحلية.';
      _emitProgress(
        LanTransferProgressEvent(
          direction: 'outgoing',
          stage: 'failed',
          progress: 1,
          fileName: fileName,
          peerIp: trimmedIp,
          message: message,
        ),
        onProgress,
      );
      return LanSendFileResult(success: false, message: message);
    } catch (error) {
      final message = error.toString();
      _emitProgress(
        LanTransferProgressEvent(
          direction: 'outgoing',
          stage: 'failed',
          progress: 1,
          fileName: fileName,
          peerIp: trimmedIp,
          message: message,
        ),
        onProgress,
      );
      return LanSendFileResult(success: false, message: message);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      _applyCorsHeaders(request.response);
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final pathValue = request.uri.path;
      if (request.method == 'GET' && pathValue == '/lan-transfer/info') {
        await _writeJsonResponse(
          request.response,
          HttpStatus.ok,
          <String, dynamic>{
            'success': true,
            'port': kLanFileTransferPort,
            'ips': localIpv4s,
          },
        );
        return;
      }

      if (request.method == 'POST' && pathValue == '/lan-transfer/request') {
        await _handleTransferRequest(request);
        return;
      }

      if (request.method == 'POST' &&
          pathValue.startsWith('/lan-transfer/upload/')) {
        final transferId = pathValue.split('/').last.trim();
        await _handleTransferUpload(request, transferId);
        return;
      }

      await _writeJsonResponse(
        request.response,
        HttpStatus.notFound,
        <String, dynamic>{'success': false, 'message': 'المسار غير موجود.'},
      );
    } catch (error) {
      await _writeJsonResponse(
        request.response,
        HttpStatus.internalServerError,
        <String, dynamic>{'success': false, 'message': error.toString()},
      );
    }
  }

  Future<void> _handleTransferRequest(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    final body = raw.trim().isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final fileName = (body['fileName']?.toString().trim().isNotEmpty == true)
        ? body['fileName'].toString().trim()
        : 'file';
    final fileSizeBytes =
        int.tryParse(body['fileSizeBytes']?.toString() ?? '') ?? 0;
    final senderName =
        (body['senderName']?.toString().trim().isNotEmpty == true)
        ? body['senderName'].toString().trim()
        : 'مستخدم';
    final senderIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final requestId = _randomId();
    final pending = _PendingLanTransfer(
      requestId: requestId,
      senderName: senderName,
      senderIp: senderIp,
      fileName: fileName,
      fileSizeBytes: fileSizeBytes,
      mimeType: body['mimeType']?.toString(),
    );
    _pendingTransfers[requestId] = pending;

    _incomingController.add(
      LanIncomingTransferRequest._(
        requestId: requestId,
        senderName: senderName,
        senderIp: senderIp,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes,
        mimeType: body['mimeType']?.toString(),
        onAccept: (saveDirectoryPath) async {
          final outputPath = await _resolveOutputPath(
            fileName: fileName,
            preferredDirectoryPath: saveDirectoryPath,
          );
          pending.outputFile = File(outputPath);
          if (!pending.decision.isCompleted) {
            pending.decision.complete(
              _LanDecision.accepted(savePath: outputPath),
            );
          }
        },
        onReject: () async {
          if (!pending.decision.isCompleted) {
            pending.decision.complete(const _LanDecision.rejected());
          }
        },
      ),
    );

    final decision = await pending.decision.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => const _LanDecision.rejected(
        message: 'انتهت مهلة قبول الاستلام على الجهاز الآخر.',
      ),
    );

    if (!decision.accepted) {
      _pendingTransfers.remove(requestId);
      await _writeJsonResponse(
        request.response,
        HttpStatus.conflict,
        <String, dynamic>{
          'accepted': false,
          'message': decision.message ?? 'تم رفض استلام الملف على هذا الجهاز.',
        },
      );
      return;
    }

    await _writeJsonResponse(request.response, HttpStatus.ok, <String, dynamic>{
      'accepted': true,
      'transferId': requestId,
    });
  }

  Future<void> _handleTransferUpload(
    HttpRequest request,
    String transferId,
  ) async {
    final pending = _pendingTransfers[transferId];
    if (pending == null || pending.outputFile == null) {
      await _writeJsonResponse(
        request.response,
        HttpStatus.notFound,
        <String, dynamic>{
          'success': false,
          'message': 'طلب النقل غير صالح أو منتهي.',
        },
      );
      return;
    }

    final total = request.contentLength;
    final sink = pending.outputFile!.openWrite();
    var received = 0;
    try {
      await for (final chunk in request) {
        received += chunk.length;
        sink.add(chunk);
        final ratio = total <= 0
            ? 0.0
            : (received / total).clamp(0, 1).toDouble();
        _emitProgress(
          LanTransferProgressEvent(
            direction: 'incoming',
            stage: 'receiving',
            progress: ratio,
            fileName: pending.fileName,
            peerIp: pending.senderIp,
            message: 'جارٍ استقبال الملف ${(ratio * 100).toStringAsFixed(0)}%',
          ),
        );
      }
      await sink.flush();
      await sink.close();
      _emitProgress(
        LanTransferProgressEvent(
          direction: 'incoming',
          stage: 'completed',
          progress: 1,
          fileName: pending.fileName,
          peerIp: pending.senderIp,
          message: 'تم استلام الملف عبر الشبكة المحلية.',
          savedPath: pending.outputFile!.path,
        ),
      );
      await _writeJsonResponse(
        request.response,
        HttpStatus.ok,
        <String, dynamic>{
          'success': true,
          'message': 'تم استلام الملف بنجاح.',
          'savedPath': pending.outputFile!.path,
        },
      );
    } catch (error) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await pending.outputFile!.delete();
      } catch (_) {}
      _emitProgress(
        LanTransferProgressEvent(
          direction: 'incoming',
          stage: 'failed',
          progress: 1,
          fileName: pending.fileName,
          peerIp: pending.senderIp,
          message: error.toString(),
        ),
      );
      await _writeJsonResponse(
        request.response,
        HttpStatus.internalServerError,
        <String, dynamic>{'success': false, 'message': error.toString()},
      );
    } finally {
      _pendingTransfers.remove(transferId);
    }
  }

  Future<void> _writeJsonResponse(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> payload,
  ) async {
    response.statusCode = statusCode;
    _applyCorsHeaders(response);
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }

  void _applyCorsHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, '*');
    response.headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, POST, OPTIONS',
    );
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      'content-type, accept',
    );
    response.headers.set('Access-Control-Allow-Private-Network', 'true');
    response.headers.set(HttpHeaders.accessControlMaxAgeHeader, '86400');
  }

  Future<List<String>> _resolveLocalIpv4s() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final addresses = <String>{};
    for (final iface in interfaces) {
      for (final address in iface.addresses) {
        if (address.type != InternetAddressType.IPv4) {
          continue;
        }
        if (address.isLoopback) {
          continue;
        }
        final value = address.address.trim();
        if (value.isEmpty) {
          continue;
        }
        addresses.add(value);
      }
    }
    return addresses.toList()..sort();
  }

  String _ipv4SubnetKey(String rawIp) {
    final normalized = normalizeIpAddress(rawIp);
    final parts = normalized.split('.');
    if (parts.length != 4) {
      return '';
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  Future<String> _resolveOutputPath({
    required String fileName,
    String? preferredDirectoryPath,
  }) async {
    final targetDirectory = await _resolveOutputDirectory(
      preferredDirectoryPath,
    );
    await targetDirectory.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final baseName = p.basenameWithoutExtension(
      safeName.isEmpty ? 'file' : safeName,
    );
    final extension = p.extension(safeName);
    var candidate = p.join(targetDirectory.path, '$baseName$extension');
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(
        targetDirectory.path,
        '$baseName ($counter)$extension',
      );
      counter += 1;
    }
    return candidate;
  }

  Future<Directory> _resolveOutputDirectory(
    String? preferredDirectoryPath,
  ) async {
    final preferred = preferredDirectoryPath?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return Directory(preferred);
    }
    return const LocalMediaStorageService().documentsDirectory();
  }

  void _emitProgress(
    LanTransferProgressEvent event, [
    void Function(LanTransferProgressEvent event)? onProgress,
  ]) {
    _progressController.add(event);
    onProgress?.call(event);
  }

  Duration _transferTimeoutForBytes(int bytes) {
    final megaBytes = bytes / (1024 * 1024);
    final minutes = megaBytes <= 8 ? 2 : (2 + (megaBytes / 10).ceil());
    return Duration(minutes: minutes.clamp(2, 20));
  }

  String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _guessMimeType(String fileName) {
    final extension = p.extension(fileName).toLowerCase();
    return switch (extension) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.mp4' => 'video/mp4',
      '.zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }

  Uri _buildLanUri(String targetIp, String pathValue) {
    final normalized = normalizeIpAddress(targetIp);
    return Uri(
      scheme: 'http',
      host: normalized,
      port: kLanFileTransferPort,
      path: pathValue,
    );
  }
}

class _PendingLanTransfer {
  _PendingLanTransfer({
    required this.requestId,
    required this.senderName,
    required this.senderIp,
    required this.fileName,
    required this.fileSizeBytes,
    required this.mimeType,
  });

  final String requestId;
  final String senderName;
  final String senderIp;
  final String fileName;
  final int fileSizeBytes;
  final String? mimeType;
  final Completer<_LanDecision> decision = Completer<_LanDecision>();
  File? outputFile;
}

class _LanDecision {
  const _LanDecision._({required this.accepted, this.savePath, this.message});

  const _LanDecision.accepted({required String savePath})
    : this._(accepted: true, savePath: savePath);

  const _LanDecision.rejected({String? message})
    : this._(accepted: false, message: message);

  final bool accepted;
  final String? savePath;
  final String? message;
}
