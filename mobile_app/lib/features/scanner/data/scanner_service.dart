import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/services/permission_request_coordinator.dart';

class ScannerPermissionDeniedException implements Exception {
  const ScannerPermissionDeniedException({
    required this.permission,
    this.permanentlyDenied = false,
  });

  final String permission;
  final bool permanentlyDenied;

  @override
  String toString() {
    if (permanentlyDenied) {
      return 'تم رفض إذن $permission نهائيًا. افتح إعدادات التطبيق واسمح به.';
    }
    return 'لم يتم منح إذن $permission.';
  }
}

class ScannerService {
  Future<List<String>?> scanMultiplePages() async {
    await _ensureScannerPermissions();

    try {
      final options = DocumentScannerOptions(
        mode: ScannerMode.full,
        pageLimit: 25,
        isGalleryImport: true,
      );

      final scanner = DocumentScanner(options: options);
      final result = await scanner.scanDocument();
      scanner.close();

      return result.images;
    } catch (e) {
      debugPrint('Scanner error: $e');
      return null;
    }
  }

  Future<String?> scanSinglePage() async {
    final pages = await scanMultiplePages();
    if (pages == null || pages.isEmpty) {
      return null;
    }
    return pages.first;
  }

  Future<void> _ensureScannerPermissions() async {
    final cameraStatus = await PermissionRequestCoordinator.run(
      Permission.camera.request,
    );
    if (!cameraStatus.isGranted) {
      throw ScannerPermissionDeniedException(
        permission: 'الكاميرا',
        permanentlyDenied:
            cameraStatus.isPermanentlyDenied || cameraStatus.isRestricted,
      );
    }

    if (Platform.isIOS) {
      final photosStatus = await PermissionRequestCoordinator.run(
        Permission.photos.request,
      );
      if (!photosStatus.isGranted && !photosStatus.isLimited) {
        throw ScannerPermissionDeniedException(
          permission: 'الصور',
          permanentlyDenied:
              photosStatus.isPermanentlyDenied || photosStatus.isRestricted,
        );
      }
    }
  }
}
