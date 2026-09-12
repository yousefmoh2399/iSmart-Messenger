import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/remote_desktop_file_service.dart';
import '../../../shared/services/remote_print_service.dart';

class UploadSummaryScreen extends ConsumerStatefulWidget {
  const UploadSummaryScreen({super.key, required this.pendingUpload});

  final PendingUpload pendingUpload;

  @override
  ConsumerState<UploadSummaryScreen> createState() =>
      _UploadSummaryScreenState();
}

class _PrinterSelectionResult {
  const _PrinterSelectionResult({
    required this.confirmed,
    required this.printerName,
  });

  final bool confirmed;
  final String? printerName;
}

class _UploadSummaryScreenState extends ConsumerState<UploadSummaryScreen> {
  bool _isUploading = false;
  double _progress = 0;
  bool _uploadSucceeded = false;
  bool _isPrinting = false;
  final Set<String> _printingItemIds = <String>{};
  final Map<String, String> _itemIdToClientRequestId = <String, String>{};
  bool _isSavingToDesktop = false;
  double _desktopSaveProgress = 0;
  String? _desktopSaveStageMessage;

  Future<void> _upload() async {
    final repository = ref.read(documentRepositoryProvider);
    final pendingController = ref.read(
      pendingUploadsControllerProvider.notifier,
    );
    final remoteController = ref.read(
      remoteDocumentsControllerProvider.notifier,
    );

    setState(() {
      _isUploading = true;
      _progress = 0;
    });

    try {
      await repository.uploadPendingDocument(
        widget.pendingUpload,
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() {
              _progress = sent / total;
            });
          }
        },
      );
      if (!mounted) return;
      await pendingController.removeById(widget.pendingUpload.id);
      if (!mounted) return;
      await remoteController.refresh();
      if (!mounted) return;
      setState(() {
        _uploadSucceeded = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم الرفع بنجاح')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<_PrinterSelectionResult> _pickPrinterName(
    RemotePrintCatalog catalog,
  ) async {
    final prefs = ref.read(userPreferencesControllerProvider).valueOrNull;
    String? selected = prefs?.preferredPrinterName ?? catalog.defaultPrinter;
    final resolved = await showModalBottomSheet<_PrinterSelectionResult>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'اختيار الطابعة',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  RadioListTile<String?>(
                    value: null,
                    groupValue: selected,
                    title: const Text('الطابعة الافتراضية'),
                    onChanged: (value) => setModalState(() => selected = value),
                  ),
                  ...catalog.printers.map(
                    (printer) => RadioListTile<String?>(
                      value: printer,
                      groupValue: selected,
                      title: Text(printer),
                      onChanged: (value) =>
                          setModalState(() => selected = value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(
                            const _PrinterSelectionResult(
                              confirmed: false,
                              printerName: null,
                            ),
                          ),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(
                            _PrinterSelectionResult(
                              confirmed: true,
                              printerName: selected,
                            ),
                          ),
                          child: const Text('تأكيد'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final result =
        resolved ??
        const _PrinterSelectionResult(confirmed: false, printerName: null);
    if (result.confirmed) {
      await ref
          .read(userPreferencesControllerProvider.notifier)
          .setPreferredPrinterName(result.printerName);
    }
    return result;
  }

  Future<void> _sharePendingFile() async {
    try {
      final file = File(widget.pendingUpload.filePath);
      if (await file.exists()) {
        final xFile = XFile(
          widget.pendingUpload.filePath,
          mimeType: 'application/pdf',
        );
        await Share.shareXFiles([xFile], text: widget.pendingUpload.fileName);
      } else {
        throw Exception('الملف غير موجود.');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _printPendingFile() async {
    final itemId = widget.pendingUpload.id;
    if (_printingItemIds.contains(itemId)) {
      return;
    }

    setState(() {
      _isPrinting = true;
      _printingItemIds.add(itemId);
    });

    final clientRequestId = _itemIdToClientRequestId.putIfAbsent(
      itemId,
      () => const Uuid().v4(),
    );

    try {
      final printService = ref.read(remotePrintServiceProvider);
      final catalog = await printService.fetchCatalog();
      if (!catalog.hasDesktop) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد تطبيق كمبيوتر متصل بنفس الحساب للطباعة.'),
          ),
        );
        return;
      }

      final selection = await _pickPrinterName(catalog);
      if (!mounted) return;
      if (!selection.confirmed) return;
      final result = await printService.requestPrintFromLocalFile(
        filePath: widget.pendingUpload.filePath,
        fileName: widget.pendingUpload.fileName,
        mimeType: 'application/pdf',
        preferredPrinterName: selection.printerName,
        source: 'mobile_scan_summary',
        clientRequestId: clientRequestId,
      );

      if (result.success) {
        _itemIdToClientRequestId.remove(itemId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _printingItemIds.remove(itemId);
        });
      }
    }
  }

  Future<void> _savePendingToDesktop() async {
    setState(() {
      _isSavingToDesktop = true;
      _desktopSaveProgress = 0.05;
      _desktopSaveStageMessage = 'جاري التحقق...';
    });
    try {
      final desktopFileService = ref.read(remoteDesktopFileServiceProvider);
      final authUser = ref.read(authControllerProvider).valueOrNull;
      final maxInlineBytes = authUser?.role == 'admin'
          ? kAdminInlineFileSaveBytes
          : kMaxInlineFileSaveBytes;
      final status = await desktopFileService.fetchStatus();
      if (!status.hasDesktop) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد تطبيق كمبيوتر متصل بنفس الحساب حاليًا.'),
          ),
        );
        return;
      }

      setState(() {
        _desktopSaveStageMessage = 'جاري تجهيز الملف...';
      });
      final result = await desktopFileService.requestSaveFromLocalFile(
        filePath: widget.pendingUpload.filePath,
        fileName: widget.pendingUpload.fileName,
        mimeType: 'application/pdf',
        source: 'mobile_upload_summary_save_to_desktop',
        maxInlineFileBytes: maxInlineBytes,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _desktopSaveProgress = progress.progress;
            _desktopSaveStageMessage = _resolveDesktopStageMessage(progress);
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      if (!result.success) {
        return;
      }
      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .removeById(widget.pendingUpload.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _isSavingToDesktop = false;
          _desktopSaveProgress = 0;
          _desktopSaveStageMessage = null;
        });
      }
    }
  }

  String _resolveDesktopStageMessage(RemoteDesktopTransferProgress progress) {
    switch (progress.stage) {
      case 'validating':
        return 'جاري تجهيز الملف...';
      case 'reading':
        return 'جاري قراءة الملف...';
      case 'encoding':
        return 'جاري تجهيز الملف للإرسال...';
      case 'sending':
        return 'جاري إرسال الطلب إلى الكمبيوتر...';
      case 'waiting_desktop':
        return 'تم الإرسال، جاري انتظار الكمبيوتر...';
      case 'completed':
        return 'تم حفظ الملف على الكمبيوتر.';
      case 'failed':
        return 'تعذر إكمال الإرسال.';
      default:
        return progress.message.trim().isEmpty
            ? 'جاري الإرسال...'
            : progress.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final upload = widget.pendingUpload;

    return Scaffold(
      appBar: AppBar(title: const Text('ملخص الملف')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      upload.fileName,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    _InfoRow(
                      label: 'عدد الصفحات',
                      value: '${upload.pageCount}',
                    ),
                    _InfoRow(
                      label: 'حجم الملف',
                      value: formatFileSize(upload.fileSize),
                    ),
                    _InfoRow(
                      label: 'تاريخ الإنشاء',
                      value: formatDate(upload.createdAt),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isSavingToDesktop) ...[
              LinearProgressIndicator(
                value: _desktopSaveProgress <= 0
                    ? null
                    : _desktopSaveProgress.clamp(0, 1),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _desktopSaveStageMessage ?? 'جاري الإرسال...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(_desktopSaveProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            if (_isUploading) ...[
              LinearProgressIndicator(
                value: _progress <= 0 ? null : _progress.clamp(0, 1),
              ),
              const SizedBox(height: 12),
              Text(
                'جاري رفع الملف... ${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],
            FilledButton.icon(
              onPressed: _isSavingToDesktop || _uploadSucceeded
                  ? null
                  : _savePendingToDesktop,
              icon: _isSavingToDesktop
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.computer_rounded),
              label: const Text('حفظ مباشر على الكمبيوتر'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _uploadSucceeded ? null : _sharePendingFile,
              icon: const Icon(Icons.share_rounded),
              label: const Text('مشاركة / حفظ في الهاتف'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _uploadSucceeded ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.save_outlined),
              label: const Text('الاحتفاظ به في الموبايل فقط'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isPrinting || _uploadSucceeded
                  ? null
                  : _printPendingFile,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_rounded),
              label: const Text('طباعة عبر الكمبيوتر'),
            ),
            const SizedBox(height: 12),
            if (_uploadSucceeded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'تم الرفع بنجاح! تجد الملف الآن في الملفات السحابية ويمكنك إرساله للشات من هناك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.green),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _upload,
                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_rounded),
                label: const Text('رفع وحفظ في السحابة'),
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
