// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

Timer? _titleAttentionTimer;
String? _originalTitle;
bool _visibilityListenerRegistered = false;
StreamSubscription<html.Event>? _electronTrayActionSubscription;

JSObject? get _electronBridgeInterop {
  try {
    if (globalContext.has('electronBridge')) {
      return globalContext.getProperty<JSObject>('electronBridge'.toJS);
    }
  } catch (_) {
    // ignore
  }

  return null;
}

JsObject? get _electronBridgeJs {
  try {
    if (context.hasProperty('electronBridge')) {
      final bridge = context['electronBridge'];
      if (bridge is JsObject) {
        return bridge;
      }
    }
  } catch (_) {
    // ignore
  }
  return null;
}

bool _looksLikeElectron() {
  try {
    return html.window.navigator.userAgent.toLowerCase().contains('electron');
  } catch (_) {
    return false;
  }
}

bool isElectron() =>
    _electronBridgeInterop != null ||
    _electronBridgeJs != null ||
    _looksLikeElectron();

Future<bool> secureStoreSet(String key, String value) async {
  if (!isElectron()) {
    return false;
  }
  final result = _asStringMap(
    await _callElectron('secureStoreSet', {'key': key, 'value': value}),
  );
  return result['success'] == true;
}

Future<String?> secureStoreGet(String key) async {
  if (!isElectron()) {
    return null;
  }
  final result = _asStringMap(await _callElectron('secureStoreGet', key));
  if (result['success'] != true) {
    return null;
  }
  final value = result['value'];
  return value is String && value.isNotEmpty ? value : null;
}

Future<bool> secureStoreDelete(String key) async {
  if (!isElectron()) {
    return false;
  }
  final result = _asStringMap(await _callElectron('secureStoreDelete', key));
  return result['success'] == true;
}

Future<void> electronDebugLog(
  String scope,
  String message, [
  Map<String, Object?>? details,
]) async {
  if (!isElectron()) {
    return;
  }
  try {
    await _callElectron('debugLog', {
      'scope': scope,
      'message': message,
      if (details != null) 'details': details,
    });
  } catch (_) {}
}

void setElectronTrayActionHandler(void Function(String action)? handler) {
  _electronTrayActionSubscription?.cancel();
  _electronTrayActionSubscription = null;
  if (handler == null) {
    return;
  }
  _electronTrayActionSubscription = html.window.on['electron-tray-action']
      .listen((event) {
        final detail = (event as dynamic).detail;
        if (detail is String && detail.trim().isNotEmpty) {
          handler(detail.trim());
        }
      });
}

Future<dynamic> _callElectron(String method, [Object? argument]) async {
  var bridge = _electronBridgeInterop;
  var jsBridge = _electronBridgeJs;
  if (bridge == null && jsBridge == null && _looksLikeElectron()) {
    for (var attempt = 0; attempt < 10; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      bridge = _electronBridgeInterop;
      jsBridge = _electronBridgeJs;
      if (bridge != null || jsBridge != null) {
        break;
      }
    }
  }
  if (bridge != null) {
    final promise = bridge.callMethodVarArgs<JSPromise<JSAny?>>(
      method.toJS,
      argument == null ? const <JSAny?>[] : <JSAny?>[argument.jsify()],
    );
    return (await promise.toDart).dartify();
  }

  if (jsBridge == null) {
    throw UnsupportedError('Electron bridge is not available.');
  }
  final jsArgument = argument == null ? null : JsObject.jsify(argument);
  return _awaitJsPromise(
    jsBridge.callMethod(method, jsArgument == null ? const [] : [jsArgument]),
  );
}

Future<dynamic> _awaitJsPromise(dynamic promise) {
  final completer = Completer<dynamic>();
  if (promise is! JsObject) {
    completer.complete(promise);
    return completer.future;
  }
  promise.callMethod('then', [
    JsFunction.withThis((_, dynamic value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }),
  ]);
  promise.callMethod('catch', [
    JsFunction.withThis((_, dynamic error) {
      if (!completer.isCompleted) {
        completer.completeError(error ?? 'Electron promise rejected.');
      }
    }),
  ]);
  return completer.future;
}

Map<String, dynamic> _asStringMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is JsObject) {
    final result = <String, dynamic>{};
    for (final key in const [
      'success',
      'accepted',
      'base64',
      'contentType',
      'message',
      'value',
      'statusCode',
      'port',
      'ip',
      'peerIp',
      'peerIps',
      'ips',
      'hostName',
      'localIp',
      'localIps',
      'osName',
      'osVersion',
      'architecture',
      'isVisible',
      'isMinimized',
      'isForeground',
      'path',
      'savedPath',
      'transferId',
      'fileName',
      'fileSizeBytes',
      'canceled',
      'policy',
      'transfers',
      'inbox',
      'auditLogs',
      'notifications',
    ]) {
      if (value.hasProperty(key)) {
        result[key] = value[key];
      }
    }
    return result;
  }
  final dartValue = value;
  if (dartValue is Map) {
    return Map<String, dynamic>.from(dartValue);
  }
  return <String, dynamic>{};
}

Future<Map<String, dynamic>> getElectronDeviceInfo() async {
  return _asStringMap(await _callElectron('getDeviceInfo'));
}

Future<List<Map<String, dynamic>>> getElectronPrinters() async {
  final raw = await _callElectron('getPrinters');
  if (raw is! List) {
    return const <Map<String, dynamic>>[];
  }
  return raw
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList();
}

Future<Map<String, dynamic>?> getElectronWindowState() async {
  if (!isElectron()) {
    return null;
  }
  try {
    return _asStringMap(await _callElectron('getWindowState'));
  } catch (_) {
    return null;
  }
}

Future<bool> setElectronWindowTheme(String mode) async {
  if (!isElectron()) {
    return false;
  }
  try {
    final normalized = mode == 'dark' ? 'dark' : 'light';
    final result = _asStringMap(
      await _callElectron('setWindowTheme', {'mode': normalized}),
    );
    return result['success'] == true;
  } catch (_) {
    return false;
  }
}

Future<String?> pickElectronDirectory({
  String? title,
  String? defaultPath,
}) async {
  if (!isElectron()) {
    return null;
  }
  final result = _asStringMap(
    await _callElectron('pickDirectory', {
      'title': title,
      'defaultPath': defaultPath,
    }),
  );
  if (result['success'] == true) {
    final path = result['path']?.toString().trim();
    return path == null || path.isEmpty ? null : path;
  }
  return null;
}

Future<Uint8List> fetchElectronBytes({
  required String url,
  Map<String, String>? headers,
}) async {
  final dataUri = await fetchElectronDataUri(url: url, headers: headers);
  final commaIndex = dataUri.indexOf(',');
  final base64Value = commaIndex >= 0 ? dataUri.substring(commaIndex + 1) : '';
  if (base64Value.isEmpty) throw StateError('Image response is empty.');
  return base64Decode(base64Value);
}

Future<String> fetchElectronDataUri({
  required String url,
  Map<String, String>? headers,
  String? fallbackMimeType,
}) async {
  final result = _asStringMap(
    await _callElectron('fetchBase64', {
      'url': url,
      'headers': headers ?? const <String, String>{},
    }),
  );
  if (result['success'] != true) {
    throw StateError(result['message']?.toString() ?? 'Image fetch failed.');
  }
  final base64Value = result['base64']?.toString() ?? '';
  if (base64Value.isEmpty) {
    throw StateError('Image response is empty.');
  }
  final contentType = result['contentType']?.toString().split(';').first.trim();
  final mimeType = contentType == null || contentType.isEmpty
      ? (fallbackMimeType?.trim().isNotEmpty == true
            ? fallbackMimeType!.trim()
            : 'image/*')
      : contentType;
  return 'data:$mimeType;base64,$base64Value';
}

Future<String> fetchElectronObjectUrl({
  required String url,
  Map<String, String>? headers,
  String? fallbackMimeType,
}) async {
  final dataUri = await fetchElectronDataUri(
    url: url,
    headers: headers,
    fallbackMimeType: fallbackMimeType,
  );
  final commaIndex = dataUri.indexOf(',');
  final metadata = commaIndex >= 0 ? dataUri.substring(0, commaIndex) : '';
  final base64Value = commaIndex >= 0 ? dataUri.substring(commaIndex + 1) : '';
  if (base64Value.isEmpty) {
    throw StateError('Image response is empty.');
  }
  final mimeMatch = RegExp(r'^data:([^;,]+)').firstMatch(metadata);
  final mimeType = mimeMatch?.group(1) ?? 'image/png';
  final bytes = base64Decode(base64Value);
  return html.Url.createObjectUrlFromBlob(html.Blob(<Object>[bytes], mimeType));
}

void revokeObjectUrl(String url) {
  if (url.startsWith('blob:')) {
    html.Url.revokeObjectUrl(url);
  }
}

Future<String?> downloadBytes({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
  String? preferredDirectoryPath,
}) async {
  if (isElectron()) {
    final result = _asStringMap(
      await _callElectron('saveBase64', {
        'base64': base64Encode(bytes),
        'fileName': fileName,
        'mimeType': mimeType,
        if (preferredDirectoryPath != null &&
            preferredDirectoryPath.trim().isNotEmpty)
          'directoryPath': preferredDirectoryPath.trim(),
      }),
    );
    if (result['success'] != true) {
      throw Exception(
        result['message']?.toString() ?? 'Electron failed to save file.',
      );
    }
    final savedPath = result['savedPath']?.toString().trim();
    return savedPath == null || savedPath.isEmpty ? null : savedPath;
  }
  final blob = html.Blob([bytes], mimeType ?? 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none'
      ..click();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
  return null;
}

Future<String?> getElectronStorageRoot() async {
  if (!isElectron()) {
    return null;
  }
  final result = _asStringMap(await _callElectron('getStorageRoot'));
  if (result['success'] != true) {
    return null;
  }
  final path = result['path']?.toString().trim();
  return path == null || path.isEmpty ? null : path;
}

Future<void> initializeElectronStorage({String? preferredDirectoryPath}) async {
  if (!isElectron()) {
    return;
  }
  await _callElectron('initializeStorage', {
    if (preferredDirectoryPath != null &&
        preferredDirectoryPath.trim().isNotEmpty)
      'directoryPath': preferredDirectoryPath.trim(),
  });
}

Future<bool> appendElectronErrorLog({
  required String entry,
  String? preferredDirectoryPath,
}) async {
  if (!isElectron()) {
    return false;
  }
  final result = _asStringMap(
    await _callElectron('appendErrorLog', {
      'entry': entry,
      if (preferredDirectoryPath != null &&
          preferredDirectoryPath.trim().isNotEmpty)
        'directoryPath': preferredDirectoryPath.trim(),
    }),
  );
  return result['success'] == true;
}

Future<bool> electronFileExists(String filePath) async {
  if (!isElectron()) {
    return false;
  }
  final result = _asStringMap(
    await _callElectron('fileExists', {'path': filePath}),
  );
  return result['success'] == true && result['exists'] == true;
}

Future<bool> openElectronLocalFile(String filePath) async {
  if (!isElectron()) {
    return false;
  }
  final result = _asStringMap(
    await _callElectron('openLocalFile', {'path': filePath}),
  );
  return result['success'] == true;
}

Future<void> archiveElectronChatAttachment({
  required String messageId,
  required String sha256Hex,
  required String fileName,
  required Uint8List bytes,
  String? preferredDirectoryPath,
}) async {
  if (!isElectron()) return;
  await _callElectron('archiveChatAttachment', {
    'messageId': messageId,
    'sha256Hex': sha256Hex,
    'fileName': fileName,
    'base64': base64Encode(bytes),
    if (preferredDirectoryPath != null &&
        preferredDirectoryPath.trim().isNotEmpty)
      'directoryPath': preferredDirectoryPath.trim(),
  });
}

Future<void> cacheElectronChatAttachment({
  required String messageId,
  required String fileName,
  required Uint8List bytes,
  String? preferredDirectoryPath,
}) async {
  if (!isElectron()) return;
  await _callElectron('cacheChatAttachment', {
    'messageId': messageId,
    'fileName': fileName,
    'base64': base64Encode(bytes),
    if (preferredDirectoryPath != null &&
        preferredDirectoryPath.trim().isNotEmpty)
      'directoryPath': preferredDirectoryPath.trim(),
  });
}

Future<Uint8List?> readElectronCachedChatAttachment({
  required String messageId,
  required String fileName,
  String? preferredDirectoryPath,
}) async {
  if (!isElectron()) return null;
  final result = _asStringMap(
    await _callElectron('readChatAttachmentCache', {
      'messageId': messageId,
      'fileName': fileName,
      if (preferredDirectoryPath != null &&
          preferredDirectoryPath.trim().isNotEmpty)
        'directoryPath': preferredDirectoryPath.trim(),
    }),
  );
  if (result['success'] != true) return null;
  final base64Value = result['base64']?.toString() ?? '';
  if (base64Value.isEmpty) return null;
  return base64Decode(base64Value);
}

Future<Uint8List?> readElectronArchivedChatAttachment({
  required String messageId,
  required String sha256Hex,
  String? preferredDirectoryPath,
}) async {
  if (!isElectron()) return null;
  final result = _asStringMap(
    await _callElectron('readChatArchive', {
      'messageId': messageId,
      'sha256Hex': sha256Hex,
      if (preferredDirectoryPath != null &&
          preferredDirectoryPath.trim().isNotEmpty)
        'directoryPath': preferredDirectoryPath.trim(),
    }),
  );
  if (result['success'] != true) return null;
  final base64Value = result['base64']?.toString() ?? '';
  if (base64Value.isEmpty) return null;
  return base64Decode(base64Value);
}

Future<void> openUrlInNewTab(String url) async {
  if (isElectron()) {
    await _callElectron('openUrl', url);
    return;
  }
  html.window.open(url, '_blank');
}

Future<void> printUrl(
  String url, {
  String? printerName,
  String? jobId,
  bool? disableAdobeFallback,
}) async {
  if (isElectron()) {
    await _callElectron('printUrl', {
      'url': url,
      'printerName': printerName,
      'jobId': jobId,
      'disableAdobeFallback': disableAdobeFallback,
    });
    return;
  }
  final frame = html.IFrameElement()
    ..src = url
    ..style.position = 'fixed'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.border = '0';
  html.document.body?.append(frame);
  try {
    await frame.onLoad.first.timeout(const Duration(seconds: 15));
  } catch (_) {}
  final contentWindow = frame.contentWindow;
  if (contentWindow != null) {
    (contentWindow as dynamic).focus();
    (contentWindow as dynamic).print();
  } else {
    html.window.open(url, '_blank');
  }
  Future<void>.delayed(const Duration(minutes: 2), frame.remove);
}

Future<void> printBytes({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
  String? printerName,
  String? jobId,
  bool? disableAdobeFallback,
}) async {
  if (isElectron()) {
    await _callElectron('printBase64', {
      'base64': base64Encode(bytes),
      'fileName': fileName,
      'mimeType': mimeType,
      'printerName': printerName,
      'jobId': jobId,
      'disableAdobeFallback': disableAdobeFallback,
    });
    return;
  }
  final blob = html.Blob([bytes], mimeType ?? 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    await printUrl(url);
  } finally {
    Future<void>.delayed(
      const Duration(minutes: 2),
      () => html.Url.revokeObjectUrl(url),
    );
  }
}

Future<void> showBrowserNotification({
  required String title,
  required String body,
  bool silent = true,
  String? soundAssetPath,
}) async {
  if (isElectron()) {
    try {
      html.window.console.log(
        '[web-bridge] showBrowserNotification electron: ${title.trim()} / ${body.trim()} silent=$silent',
      );
    } catch (_) {}
    try {
      await _callElectron('notify', {
        'title': title,
        'body': body,
        'silent': silent,
        if (soundAssetPath != null && soundAssetPath.trim().isNotEmpty)
          'soundAssetPath': soundAssetPath,
      });
    } catch (e) {
      try {
        html.window.console.error('[web-bridge] notify call failed: $e');
      } catch (_) {}
    }
    return;
  }
  if (!isPageVisible()) {
    showBrowserAttention(title);
  }
  if (!html.Notification.supported) {
    return;
  }
  var permission = html.Notification.permission;
  if (permission == 'default') {
    permission = await html.Notification.requestPermission();
  }
  if (permission != 'granted') {
    return;
  }
  html.Notification(title, body: body);
}

bool isPageVisible() {
  _ensureVisibilityListener();
  final visible = html.document.visibilityState == 'visible';
  if (visible) {
    clearBrowserAttention();
  }
  return visible;
}

Future<bool> isElectronWindowForegroundVisible() async {
  if (!isElectron()) {
    return isPageVisible();
  }
  final state = await getElectronWindowState();
  if (state == null) {
    return false;
  }
  final isVisible = state['isVisible'] == true;
  final isMinimized = state['isMinimized'] == true;
  final isForeground = state['isForeground'] == true;
  return isVisible && !isMinimized && isForeground;
}

void showBrowserAttention(String title) {
  _ensureVisibilityListener();
  if (isPageVisible()) {
    return;
  }
  _originalTitle ??= html.document.title;
  final alertTitle = title.trim().isEmpty ? _originalTitle! : title.trim();
  _titleAttentionTimer ??= Timer.periodic(const Duration(milliseconds: 900), (
    _,
  ) {
    html.document.title = html.document.title == alertTitle
        ? _originalTitle!
        : alertTitle;
  });
}

void clearBrowserAttention() {
  _titleAttentionTimer?.cancel();
  _titleAttentionTimer = null;
  final original = _originalTitle;
  if (original != null && original.isNotEmpty) {
    html.document.title = original;
  }
  _originalTitle = null;
}

void _ensureVisibilityListener() {
  if (_visibilityListenerRegistered) {
    return;
  }
  _visibilityListenerRegistered = true;
  html.document.onVisibilityChange.listen((_) {
    if (html.document.visibilityState == 'visible') {
      clearBrowserAttention();
    }
  });
  html.window.onFocus.listen((_) => clearBrowserAttention());
}

Future<void> playBrowserAudioAsset(String assetPath) async {
  try {
    if (isElectron()) {
      final result = await _callElectron('playAudioAsset', {
        'assetPath': assetPath,
      });
      if (result is Map && result['success'] == false) {
        throw StateError(result['error']?.toString() ?? 'Audio failed.');
      }
      return;
    }

    String src;
    if (assetPath.startsWith('data:') ||
        assetPath.startsWith('http') ||
        assetPath.startsWith('/')) {
      src = assetPath;
    } else {
      final normalized = assetPath.replaceFirst(RegExp(r'^/+'), '');
      final webAssetPath = normalized.startsWith('assets/')
          ? 'assets/$normalized'
          : 'assets/$normalized';
      src = Uri.parse(
        html.window.location.href,
      ).resolve(webAssetPath).toString();
    }
    html.window.console.log('[web-bridge] playBrowserAudioAsset src: $src');
    final audio = html.AudioElement(src)
      ..preload = 'auto'
      ..autoplay = false;
    await audio.play();
    html.window.console.log('[web-bridge] audio.play resolved for: $src');
  } catch (e) {
    html.window.console.error('[web-bridge] playBrowserAudioAsset error: $e');
    rethrow;
  }
}

Future<Map<String, dynamic>> probeLanPeer(String targetIp) async {
  if (isElectron()) {
    return _asStringMap(await _callElectron('probeLanPeer', targetIp));
  }
  final response = await _requestJson(
    'http://$targetIp:27861/lan-transfer/info',
    method: 'GET',
  );
  return response;
}

Future<List<Map<String, dynamic>>> discoverElectronLanPeers() async {
  if (!isElectron()) {
    return const <Map<String, dynamic>>[];
  }
  final raw = await _callElectron('discoverLanPeers');
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
  if (raw is JsObject) {
    final length = raw['length'];
    if (length is int) {
      final result = <Map<String, dynamic>>[];
      for (var index = 0; index < length; index += 1) {
        result.add(_asStringMap(raw[index]));
      }
      return result;
    }
  }
  return const <Map<String, dynamic>>[];
}

Future<Map<String, dynamic>> requestLanTransfer({
  required String targetIp,
  required String fileName,
  required int fileSizeBytes,
  required String senderName,
  String? mimeType,
}) async {
  if (isElectron()) {
    return _asStringMap(
      await _callElectron('requestLanTransfer', {
        'targetIp': targetIp,
        'fileName': fileName,
        'fileSizeBytes': fileSizeBytes,
        'senderName': senderName,
        'mimeType': mimeType,
      }),
    );
  }
  return _requestJson(
    'http://$targetIp:27861/lan-transfer/request',
    method: 'POST',
    timeout: const Duration(minutes: 5),
    headers: const {'Content-Type': 'application/json'},
    sendData: jsonEncode({
      'fileName': fileName,
      'fileSizeBytes': fileSizeBytes,
      'senderName': senderName.trim().isEmpty ? 'مستخدم' : senderName.trim(),
      'mimeType': mimeType,
    }),
  );
}

Future<Map<String, dynamic>> uploadLanTransferBytes({
  required String targetIp,
  required String transferId,
  required Uint8List bytes,
  String? uploadToken,
  void Function(int sent, int total)? onProgress,
}) async {
  if (isElectron()) {
    onProgress?.call(0, bytes.length);
    final result = _asStringMap(
      await _callElectron('uploadLanTransferBytes', {
        'targetIp': targetIp,
        'transferId': transferId,
        'uploadToken': uploadToken,
        'bytes': bytes,
      }),
    );
    onProgress?.call(bytes.length, bytes.length);
    return result;
  }
  final request = html.HttpRequest();
  final completer = Completer<Map<String, dynamic>>();
  request
    ..open('POST', 'http://$targetIp:27861/lan-transfer/upload/$transferId')
    ..setRequestHeader('Content-Type', 'application/octet-stream')
    ..responseType = 'text';
  if (uploadToken != null && uploadToken.trim().isNotEmpty) {
    request.setRequestHeader('X-LAN-Transfer-Token', uploadToken.trim());
  }
  request.upload.onProgress.listen((event) {
    onProgress?.call(event.loaded ?? 0, event.total ?? bytes.length);
  });
  request.onLoadEnd.listen((_) {
    if (completer.isCompleted) return;
    final status = request.status ?? 0;
    final text = request.responseText ?? '{}';
    final decoded = _decodeJsonMap(text);
    if (status >= 200 && status < 500) {
      completer.complete(decoded);
    } else {
      completer.completeError(Exception(decoded['message'] ?? text));
    }
  });
  request.onError.listen((_) {
    if (!completer.isCompleted) {
      completer.completeError(Exception('تعذر الاتصال بالجهاز عبر الشبكة.'));
    }
  });
  request.send(bytes);
  return completer.future;
}

Future<Map<String, dynamic>> pickAndSendElectronLanFile({
  required String targetIp,
  required String senderName,
  required int maxBytes,
  String? progressToken,
  String? senderBranchCode,
  String? receiverBranchCode,
}) async {
  if (!isElectron()) {
    throw UnsupportedError('Electron bridge is not available.');
  }
  return _asStringMap(
    await _callElectron('pickAndSendLanFile', {
      'targetIp': targetIp,
      'senderName': senderName,
      'maxBytes': maxBytes,
      'progressToken': progressToken,
      'senderBranchCode': senderBranchCode,
      'receiverBranchCode': receiverBranchCode,
    }),
  );
}

Future<Map<String, dynamic>> _requestJson(
  String url, {
  required String method,
  Map<String, String>? headers,
  Object? sendData,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final request = html.HttpRequest();
  final completer = Completer<Map<String, dynamic>>();
  request
    ..open(method, url)
    ..responseType = 'text';
  for (final entry in (headers ?? const <String, String>{}).entries) {
    request.setRequestHeader(entry.key, entry.value);
  }
  request.onLoadEnd.listen((_) {
    if (completer.isCompleted) return;
    final status = request.status ?? 0;
    final text = request.responseText ?? '{}';
    final decoded = _decodeJsonMap(text);
    if (status >= 200 && status < 500) {
      completer.complete(decoded);
    } else {
      completer.completeError(Exception(decoded['message'] ?? text));
    }
  });
  request.onError.listen((_) {
    if (!completer.isCompleted) {
      completer.completeError(Exception('تعذر الاتصال بالجهاز عبر الشبكة.'));
    }
  });
  request.send(sendData);
  return completer.future.timeout(timeout);
}

Map<String, dynamic> _decodeJsonMap(String text) {
  final decoded = jsonDecode(text.trim().isEmpty ? '{}' : text);
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, dynamic>.from(decoded);
  }
  return <String, dynamic>{};
}

StreamSubscription<html.Event>? _electronUpdaterProgressSubscription;
StreamSubscription<html.Event>? _electronLanTransferProgressSubscription;
StreamSubscription<html.Event>? _electronLanReceivePendingSubscription;

void setElectronLanTransferProgressHandler(
  void Function(Map<String, dynamic> progress)? handler,
) {
  _electronLanTransferProgressSubscription?.cancel();
  _electronLanTransferProgressSubscription = null;
  if (handler == null) {
    return;
  }
  _electronLanTransferProgressSubscription = html
      .window
      .on['electron-lan-transfer-progress']
      .listen((event) {
        final detail = (event as dynamic).detail;
        if (detail is String && detail.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(detail);
            if (decoded is Map) {
              handler(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {
            // ignore malformed progress events
          }
        }
      });
}

void setElectronLanReceivePendingHandler(
  void Function(List<Map<String, dynamic>> requests)? handler,
) {
  _electronLanReceivePendingSubscription?.cancel();
  _electronLanReceivePendingSubscription = null;
  if (handler == null) {
    return;
  }
  _electronLanReceivePendingSubscription = html
      .window
      .on['electron-lan-receive-pending']
      .listen((event) {
        final detail = (event as dynamic).detail;
        if (detail is String && detail.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(detail);
            if (decoded is List) {
              handler(
                decoded
                    .whereType<Map>()
                    .map((entry) => Map<String, dynamic>.from(entry))
                    .toList(),
              );
            }
          } catch (_) {
            // ignore malformed pending events
          }
        }
      });
}

Future<List<Map<String, dynamic>>>
getPendingElectronLanReceiveRequests() async {
  if (!isElectron()) {
    return const <Map<String, dynamic>>[];
  }
  final raw = await _callElectron('getPendingLanReceiveRequests');
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
  return const <Map<String, dynamic>>[];
}

Future<Map<String, dynamic>> openPendingElectronLanReceiveDialog([
  String? requestId,
]) async {
  if (!isElectron()) {
    throw UnsupportedError('Electron bridge is not available.');
  }
  return _asStringMap(
    await _callElectron('openPendingLanReceiveDialog', requestId),
  );
}

Future<Map<String, dynamic>> getElectronTransferCenterState() async {
  if (!isElectron()) {
    return const <String, dynamic>{};
  }
  return _asStringMap(await _callElectron('getTransferCenterState'));
}

Future<Map<String, dynamic>> updateElectronTransferPolicy(
  Map<String, dynamic> policy,
) async {
  if (!isElectron()) {
    throw UnsupportedError('Electron bridge is not available.');
  }
  return _asStringMap(await _callElectron('updateTransferPolicy', policy));
}

Future<Map<String, dynamic>> markElectronTransferNotificationsRead() async {
  if (!isElectron()) {
    return const <String, dynamic>{};
  }
  return _asStringMap(await _callElectron('markTransferNotificationsRead'));
}

Future<Map<String, dynamic>> openElectronInboxFileLocation(
  String filePath,
) async {
  if (!isElectron()) {
    throw UnsupportedError('Electron bridge is not available.');
  }
  return _asStringMap(await _callElectron('openInboxFileLocation', filePath));
}

void setElectronUpdaterProgressHandler(
  void Function(Map<String, dynamic> progress)? handler,
) {
  _electronUpdaterProgressSubscription?.cancel();
  _electronUpdaterProgressSubscription = null;
  if (handler == null) {
    return;
  }
  _electronUpdaterProgressSubscription = html
      .window
      .on['electron-updater-progress']
      .listen((event) {
        final detail = (event as dynamic).detail;
        if (detail is String && detail.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(detail);
            if (decoded is Map<String, dynamic>) {
              handler(decoded);
            }
          } catch (_) {}
        }
      });
}

Future<Map<String, dynamic>> startElectronUpdate({
  required String downloadUrl,
  String? token,
  String? checksumSha256,
}) async {
  final result = await _callElectron('startUpdate', {
    'downloadUrl': downloadUrl,
    if (token != null) 'token': token,
    if (checksumSha256 != null) 'checksumSha256': checksumSha256,
  });
  return _asStringMap(result);
}

Future<Map<String, dynamic>> applyElectronUpdate() async {
  final result = await _callElectron('applyUpdate');
  return _asStringMap(result);
}

// ─── Screenshot helpers (Electron only) ──────────────────────────────────────

Future<List<Map<String, dynamic>>> electronListOpenWindows() async {
  final raw = await _callElectron('listOpenWindows');
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  if (raw is Map) {
    final result = Map<String, dynamic>.from(raw);
    if (result['windows'] is List) {
      return (result['windows'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
  }
  return const <Map<String, dynamic>>[];
}

/// Returns base64-encoded PNG data or null on failure.
/// The main process handles temp file creation internally.
Future<String?> electronCaptureWindow(int windowId) async {
  final result = _asStringMap(
    await _callElectron('captureWindow', {'windowId': windowId}),
  );
  if (result['success'] != true) return null;
  final b64 = result['base64'];
  return b64 is String && b64.isNotEmpty ? b64 : null;
}

/// Returns base64-encoded PNG data or null on failure.
Future<String?> electronCaptureScreen() async {
  final result = _asStringMap(await _callElectron('captureScreen'));
  if (result['success'] != true) return null;
  final b64 = result['base64'];
  return b64 is String && b64.isNotEmpty ? b64 : null;
}

/// Opens Remote Desktop Connection (mstsc.exe) via the main process.
Future<bool> electronOpenRdp(String ip) async {
  final result = _asStringMap(await _callElectron('openRdp', {'ip': ip}));
  return result['success'] == true;
}
