import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<String?> downloadBytes({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
  String? preferredDirectoryPath,
}) async {
  final targetFile = await _resolveDownloadFile(
    fileName,
    preferredDirectoryPath: preferredDirectoryPath,
  );
  await targetFile.parent.create(recursive: true);
  await targetFile.writeAsBytes(bytes, flush: true);
  return targetFile.path;
}

bool isElectron() => false;

Future<String?> getElectronStorageRoot() async => null;

Future<void> initializeElectronStorage({
  String? preferredDirectoryPath,
}) async {}

Future<bool> appendElectronErrorLog({
  required String entry,
  String? preferredDirectoryPath,
}) async {
  return false;
}

Future<bool> electronFileExists(String filePath) async => false;

Future<bool> openElectronLocalFile(String filePath) async => false;

Future<void> archiveElectronChatAttachment({
  required String messageId,
  required String sha256Hex,
  required String fileName,
  required Uint8List bytes,
  String? preferredDirectoryPath,
}) async {}

Future<void> cacheElectronChatAttachment({
  required String messageId,
  required String fileName,
  required Uint8List bytes,
  String? preferredDirectoryPath,
}) async {}

Future<Uint8List?> readElectronCachedChatAttachment({
  required String messageId,
  required String fileName,
  String? preferredDirectoryPath,
}) async => null;

Future<Uint8List?> readElectronArchivedChatAttachment({
  required String messageId,
  required String sha256Hex,
  String? preferredDirectoryPath,
}) async => null;

Future<bool> secureStoreSet(String key, String value) async => false;

Future<String?> secureStoreGet(String key) async => null;

Future<bool> secureStoreDelete(String key) async => false;

Future<void> electronDebugLog(
  String scope,
  String message, [
  Map<String, Object?>? details,
]) async {}

void setElectronTrayActionHandler(void Function(String action)? handler) {}

Future<Map<String, dynamic>> getElectronDeviceInfo() async {
  throw UnsupportedError('Electron is not available on this platform.');
}

Future<List<Map<String, dynamic>>> getElectronPrinters() async {
  throw UnsupportedError('Electron is not available on this platform.');
}

Future<Map<String, dynamic>?> getElectronWindowState() async {
  return null;
}

Future<bool> setElectronWindowTheme(String mode) async => false;

Future<String?> pickElectronDirectory({
  String? title,
  String? defaultPath,
}) async {
  return null;
}

Future<Uint8List> fetchElectronBytes({
  required String url,
  Map<String, String>? headers,
}) async {
  throw UnsupportedError('Electron is not available on this platform.');
}

Future<String> fetchElectronDataUri({
  required String url,
  Map<String, String>? headers,
  String? fallbackMimeType,
}) async {
  throw UnsupportedError('Electron is not available on this platform.');
}

Future<String> fetchElectronObjectUrl({
  required String url,
  Map<String, String>? headers,
  String? fallbackMimeType,
}) async {
  throw UnsupportedError('Electron is not available on this platform.');
}

void revokeObjectUrl(String url) {}

Future<void> openUrlInNewTab(String url) async {
  throw UnsupportedError('Browser windows are only available on web.');
}

Future<void> printUrl(
  String url, {
  String? printerName,
  String? jobId,
  bool? disableAdobeFallback,
}) async {
  throw UnsupportedError('Browser printing is only available on web.');
}

Future<void> printBytes({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
  String? printerName,
  String? jobId,
  bool? disableAdobeFallback,
}) async {
  throw UnsupportedError('Browser printing is only available on web.');
}

Future<void> showBrowserNotification({
  required String title,
  required String body,
  bool silent = true,
  String? soundAssetPath,
}) async {}

bool isPageVisible() => false;

Future<bool> isElectronWindowForegroundVisible() async => false;

void clearBrowserAttention() {}

Future<void> playBrowserAudioAsset(String assetPath) async {}

Future<void> playElectronAudioAsset(String assetPath) async {}

Future<Map<String, dynamic>> probeLanPeer(String targetIp) async {
  throw UnsupportedError('LAN browser probing is only available on web.');
}

Future<List<Map<String, dynamic>>> discoverElectronLanPeers() async {
  return const <Map<String, dynamic>>[];
}

Future<Map<String, dynamic>> requestLanTransfer({
  required String targetIp,
  required String fileName,
  required int fileSizeBytes,
  required String senderName,
  String? mimeType,
}) async {
  throw UnsupportedError('LAN browser transfers are only available on web.');
}

Future<Map<String, dynamic>> uploadLanTransferBytes({
  required String targetIp,
  required String transferId,
  required Uint8List bytes,
  String? uploadToken,
  void Function(int sent, int total)? onProgress,
}) async {
  throw UnsupportedError('LAN browser transfers are only available on web.');
}

Future<Map<String, dynamic>> pickAndSendElectronLanFile({
  required String targetIp,
  required String senderName,
  required int maxBytes,
  String? progressToken,
  String? senderBranchCode,
  String? receiverBranchCode,
}) async {
  throw UnsupportedError(
    'Electron LAN transfers are only available in Electron.',
  );
}

void setElectronLanTransferProgressHandler(
  void Function(Map<String, dynamic> progress)? handler,
) {}

void setElectronLanReceivePendingHandler(
  void Function(List<Map<String, dynamic>> requests)? handler,
) {}

Future<List<Map<String, dynamic>>>
getPendingElectronLanReceiveRequests() async {
  return const <Map<String, dynamic>>[];
}

Future<Map<String, dynamic>> openPendingElectronLanReceiveDialog([
  String? requestId,
]) async {
  throw UnsupportedError('Electron is not available on this platform.');
}

Future<Map<String, dynamic>> getElectronTransferCenterState() async {
  return const <String, dynamic>{};
}

Future<Map<String, dynamic>> updateElectronTransferPolicy(
  Map<String, dynamic> policy,
) async {
  throw UnsupportedError('Electron is not available on this platform.');
}

Future<Map<String, dynamic>> markElectronTransferNotificationsRead() async {
  return const <String, dynamic>{};
}

Future<Map<String, dynamic>> openElectronInboxFileLocation(
  String filePath,
) async {
  throw UnsupportedError('Electron is not available on this platform.');
}

void setElectronUpdaterProgressHandler(
  void Function(Map<String, dynamic> progress)? handler,
) {}

Future<Map<String, dynamic>> startElectronUpdate({
  required String downloadUrl,
  String? token,
  String? checksumSha256,
}) async {
  throw UnsupportedError('Electron is not available on this platform.');
}

Future<Map<String, dynamic>> applyElectronUpdate() async {
  throw UnsupportedError('Electron is not available on this platform.');
}

Future<File> _resolveDownloadFile(
  String fileName, {
  String? preferredDirectoryPath,
}) async {
  final safeName = _sanitizeFileName(fileName);
  final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
  final preferred = preferredDirectoryPath?.trim();
  final fallbackDirectory = preferred != null && preferred.isNotEmpty
      ? Directory(preferred)
      : localAppData != null && localAppData.isNotEmpty
      ? Directory(
          path.join(localAppData, 'iSmart Messenger', 'Storage', 'Documents'),
        )
      : Directory(
          path.join(
            (await getApplicationDocumentsDirectory()).path,
            'iSmart Messenger',
            'Storage',
            'Documents',
          ),
        );
  await fallbackDirectory.create(recursive: true);

  final baseName = path.basenameWithoutExtension(safeName);
  final extension = path.extension(safeName);
  var candidatePath = path.join(fallbackDirectory.path, '$baseName$extension');
  var counter = 1;
  while (await File(candidatePath).exists()) {
    candidatePath = path.join(
      fallbackDirectory.path,
      '$baseName ($counter)$extension',
    );
    counter += 1;
  }
  return File(candidatePath);
}

String _sanitizeFileName(String value) {
  final trimmed = value.trim();
  final safe = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (safe.isEmpty) {
    return 'download.bin';
  }
  return safe;
}

Future<List<Map<String, dynamic>>> electronListOpenWindows() async =>
    const <Map<String, dynamic>>[];

Future<String?> electronCaptureWindow(int windowId) async => null;

Future<String?> electronCaptureScreen() async => null;

Future<bool> electronOpenRdp(String ip) async => false;
