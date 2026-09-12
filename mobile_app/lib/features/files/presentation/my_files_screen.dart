import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'package:uuid/uuid.dart';

import '../../../core/utils/formatters.dart';
import '../../../shared/models/remote_document.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/remote_desktop_file_service.dart';
import '../../../shared/services/remote_print_service.dart';
import '../../../shared/widgets/app_loading_placeholders.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../chat/models/chat_models.dart';
import '../../../shared/models/pending_upload.dart';
import 'upload_summary_screen.dart';

class MyFilesScreen extends ConsumerStatefulWidget {
  const MyFilesScreen({super.key, this.launchDesktopSendPickerOnOpen = false});

  final bool launchDesktopSendPickerOnOpen;

  @override
  ConsumerState<MyFilesScreen> createState() => _MyFilesScreenState();
}

class _PrinterSelectionResult {
  const _PrinterSelectionResult({
    required this.confirmed,
    required this.printerName,
  });

  final bool confirmed;
  final String? printerName;
}

enum _DocumentMenuAction {
  print,
  sendToDesktop,
  sendToChat,
  share,
  rename,
  delete,
}

enum _PendingMenuAction {
  upload,
  print,
  sendToDesktop,
  sendToChat,
  share,
  open,
  delete,
}

class _MyFilesScreenState extends ConsumerState<MyFilesScreen> {
  final _searchController = TextEditingController();
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String? _downloadingFileName;
  bool _isPrinting = false;
  String? _printingFileName;
  final Set<String> _printingItemIds = <String>{};
  final Map<String, String> _itemIdToClientRequestId = <String, String>{};
  bool _isSendingToDesktop = false;
  String? _sendingFileName;
  double _desktopSendProgress = 0;
  String? _desktopSendStageMessage;
  bool _isSendingToChat = false;
  String? _sendingChatFileName;

  @override
  void initState() {
    super.initState();
    // تحديث قائمة الملفات عند كل دخول للشاشة (سواء أول مرة أو عودة من شاشة أخرى)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(remoteDocumentsControllerProvider);
      }
    });
    if (widget.launchDesktopSendPickerOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendLocalFileToDesktop();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RemoteDocument> _filter(List<RemoteDocument> documents) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return documents;
    return documents
        .where((document) => document.fileName.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _renameDocument(RemoteDocument document) async {
    final controller = TextEditingController(text: document.fileName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تسمية الملف'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'اسم الملف'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    if (!mounted) return;

    try {
      final repository = ref.read(documentRepositoryProvider);
      final controller = ref.read(remoteDocumentsControllerProvider.notifier);
      await repository.renameDocument(document.id, result);
      if (!mounted) return;
      await controller.refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تحديث اسم الملف')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _deleteDocument(RemoteDocument document) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف الملف'),
            content: Text('هل تريد حذف "${document.fileName}" نهائيًا؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;
    if (!mounted) return;

    try {
      final repository = ref.read(documentRepositoryProvider);
      final controller = ref.read(remoteDocumentsControllerProvider.notifier);
      await repository.deleteDocument(document.id);
      if (!mounted) return;
      await controller.refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حذف الملف')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _downloadAndOpen(RemoteDocument document) async {
    try {
      if (mounted) {
        setState(() {
          _isDownloading = true;
          _downloadProgress = 0;
          _downloadingFileName = document.fileName;
        });
      }
      final localPath = await ref
          .read(documentRepositoryProvider)
          .downloadDocument(
            document,
            onProgress: (received, total) {
              if (!mounted) return;
              setState(() {
                _downloadProgress = total <= 0
                    ? 0
                    : (received / total).clamp(0, 1).toDouble();
              });
            },
          );
      await OpenFilex.open(localPath);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
          _downloadingFileName = null;
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

  Future<void> _printDocument(RemoteDocument document) async {
    final itemId = document.id;
    if (_printingItemIds.contains(itemId)) {
      return;
    }

    setState(() {
      _isPrinting = true;
      _printingFileName = document.fileName;
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

      final localPath = await ref
          .read(documentRepositoryProvider)
          .downloadDocument(document);
      final result = await printService.requestPrintFromLocalFile(
        filePath: localPath,
        fileName: document.fileName,
        mimeType: document.mimeType,
        preferredPrinterName: selection.printerName,
        source: 'mobile_my_files',
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
          _printingFileName = null;
          _printingItemIds.remove(itemId);
        });
      }
    }
  }

  Future<void> _printPendingUpload(PendingUpload upload) async {
    final itemId = upload.id;
    if (_printingItemIds.contains(itemId)) {
      return;
    }

    setState(() {
      _isPrinting = true;
      _printingFileName = upload.fileName;
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
        filePath: upload.filePath,
        fileName: upload.fileName,
        mimeType: 'application/pdf',
        preferredPrinterName: selection.printerName,
        source: 'mobile_my_files_pending',
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
          _printingFileName = null;
          _printingItemIds.remove(itemId);
        });
      }
    }
  }

  Future<void> _printLocalFileFromDevice() async {
    final pick = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    final localPath = pick?.files.single.path;
    if (localPath == null || localPath.isEmpty) {
      return;
    }

    final itemId = localPath;
    if (_printingItemIds.contains(itemId)) {
      return;
    }

    final fileName = p.basename(localPath);
    setState(() {
      _isPrinting = true;
      _printingFileName = fileName;
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
        filePath: localPath,
        fileName: fileName,
        preferredPrinterName: selection.printerName,
        source: 'mobile_device_file',
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
          _printingFileName = null;
          _printingItemIds.remove(itemId);
        });
      }
    }
  }

  Future<void> _sendLocalFileToDesktop() async {
    final pick = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );
    final localPath = pick?.files.single.path;
    if (localPath == null || localPath.isEmpty) {
      return;
    }

    final fileName = p.basename(localPath);
    setState(() {
      _isSendingToDesktop = true;
      _sendingFileName = fileName;
      _desktopSendProgress = 0.05;
      _desktopSendStageMessage = 'جاري التجهيز...';
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
        _desktopSendStageMessage = 'جاري إرسال الملف إلى الكمبيوتر...';
      });
      final result = await desktopFileService.requestSaveFromLocalFile(
        filePath: localPath,
        fileName: fileName,
        source: 'mobile_device_file_transfer',
        maxInlineFileBytes: maxInlineBytes,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _desktopSendProgress = progress.progress;
            _desktopSendStageMessage = _resolveDesktopStageMessage(progress);
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isSendingToDesktop = false;
          _sendingFileName = null;
          _desktopSendProgress = 0;
          _desktopSendStageMessage = null;
        });
      }
    }
  }

  Future<void> _sendDocumentToDesktop(RemoteDocument document) async {
    setState(() {
      _isSendingToDesktop = true;
      _sendingFileName = document.fileName;
      _desktopSendProgress = 0.10;
      _desktopSendStageMessage = 'جاري التحقق...';
    });
    try {
      final desktopFileService = ref.read(remoteDesktopFileServiceProvider);
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
        _desktopSendStageMessage = 'جاري إرسال الملف إلى الكمبيوتر...';
      });
      final localPath = await ref
          .read(documentRepositoryProvider)
          .downloadDocument(document);
      final result = await desktopFileService.requestSaveFromLocalFile(
        filePath: localPath,
        fileName: document.fileName,
        mimeType: document.mimeType,
        source: 'mobile_cloud_file_transfer',
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _desktopSendProgress = progress.progress;
            _desktopSendStageMessage = _resolveDesktopStageMessage(progress);
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isSendingToDesktop = false;
          _sendingFileName = null;
          _desktopSendProgress = 0;
          _desktopSendStageMessage = null;
        });
      }
    }
  }

  Future<void> _sendPendingToDesktop(PendingUpload upload) async {
    setState(() {
      _isSendingToDesktop = true;
      _sendingFileName = upload.fileName;
      _desktopSendProgress = 0.05;
      _desktopSendStageMessage = 'جاري التحقق...';
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
        _desktopSendStageMessage = 'جاري تجهيز الملف...';
      });
      final result = await desktopFileService.requestSaveFromLocalFile(
        filePath: upload.filePath,
        fileName: upload.fileName,
        mimeType: 'application/pdf',
        source: 'mobile_my_files_pending_transfer',
        maxInlineFileBytes: maxInlineBytes,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            _desktopSendProgress = progress.progress;
            _desktopSendStageMessage = _resolveDesktopStageMessage(progress);
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } finally {
      if (mounted) {
        setState(() {
          _isSendingToDesktop = false;
          _sendingFileName = null;
          _desktopSendProgress = 0;
          _desktopSendStageMessage = null;
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

  Future<ChatConversation?> _pickConversationForSend() async {
    final overview = ref.read(chatOverviewControllerProvider).valueOrNull;
    if (overview == null || overview.conversations.isEmpty) {
      return null;
    }
    final authUserId = ref.read(authControllerProvider).valueOrNull?.id ?? '';
    final conversations = [...overview.conversations]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        final aDate = a.lastMessage?.createdAt ?? a.updatedAt;
        final bDate = b.lastMessage?.createdAt ?? b.updatedAt;
        return bDate.compareTo(aDate);
      });

    return showModalBottomSheet<ChatConversation>(
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 520,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'اختر المحادثة',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    return ListTile(
                      leading: Icon(
                        conversation.type == 'direct'
                            ? Icons.person_outline
                            : Icons.groups_outlined,
                      ),
                      title: Text(conversation.displayTitle(authUserId)),
                      subtitle: Text(
                        conversation.type == 'direct'
                            ? 'محادثة مباشرة'
                            : 'مجموعة/غرفة',
                      ),
                      onTap: () => Navigator.of(context).pop(conversation),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendDocumentToChat(RemoteDocument document) async {
    final target = await _pickConversationForSend();
    if (target == null) {
      return;
    }
    setState(() {
      _isSendingToChat = true;
      _sendingChatFileName = document.fileName;
    });
    try {
      final localPath = await ref
          .read(documentRepositoryProvider)
          .downloadDocument(document);
      await ref
          .read(conversationMessagesControllerProvider(target.id).notifier)
          .sendFile(localPath, customFileName: document.fileName);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إرسال ${document.fileName} إلى ${target.displayTitle(ref.read(authControllerProvider).valueOrNull?.id ?? '')}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingToChat = false;
          _sendingChatFileName = null;
        });
      }
    }
  }

  Future<void> _sendPendingToChat(PendingUpload upload) async {
    final target = await _pickConversationForSend();
    if (target == null) {
      return;
    }
    setState(() {
      _isSendingToChat = true;
      _sendingChatFileName = upload.fileName;
    });
    try {
      await ref
          .read(conversationMessagesControllerProvider(target.id).notifier)
          .sendFile(upload.filePath, customFileName: upload.fileName);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إرسال ${upload.fileName} إلى ${target.displayTitle(ref.read(authControllerProvider).valueOrNull?.id ?? '')}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingToChat = false;
          _sendingChatFileName = null;
        });
      }
    }
  }

  Future<void> _uploadPendingUpload(PendingUpload upload) async {
    try {
      await ref.read(documentRepositoryProvider).uploadPendingDocument(upload);
      await ref
          .read(pendingUploadsControllerProvider.notifier)
          .removeById(upload.id);
      await ref.read(remoteDocumentsControllerProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم الرفع بنجاح')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _deletePendingUpload(PendingUpload upload) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف الملف المحلي'),
            content: Text('هل تريد حذف "${upload.fileName}" من الموبايل؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;
    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .removeById(upload.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حذف الملف المحلي')));
  }

  Future<void> _shareDocument(RemoteDocument document) async {
    try {
      final localPath = await ref
          .read(documentRepositoryProvider)
          .downloadDocument(document);
      final xFile = XFile(localPath, mimeType: 'application/pdf');
      await Share.shareXFiles([xFile], text: document.fileName);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _sharePendingUpload(PendingUpload upload) async {
    try {
      final file = File(upload.filePath);
      if (await file.exists()) {
        final xFile = XFile(upload.filePath, mimeType: 'application/pdf');
        await Share.shareXFiles([xFile], text: upload.fileName);
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

  Future<void> _handleDocumentMenuAction(
    _DocumentMenuAction action,
    RemoteDocument document,
  ) async {
    switch (action) {
      case _DocumentMenuAction.print:
        await _printDocument(document);
        return;
      case _DocumentMenuAction.sendToDesktop:
        await _sendDocumentToDesktop(document);
        return;
      case _DocumentMenuAction.sendToChat:
        await _sendDocumentToChat(document);
        return;
      case _DocumentMenuAction.share:
        await _shareDocument(document);
        return;
      case _DocumentMenuAction.rename:
        await _renameDocument(document);
        return;
      case _DocumentMenuAction.delete:
        await _deleteDocument(document);
        return;
    }
  }

  Future<void> _handlePendingMenuAction(
    _PendingMenuAction action,
    PendingUpload upload,
  ) async {
    switch (action) {
      case _PendingMenuAction.upload:
        await _uploadPendingUpload(upload);
        return;
      case _PendingMenuAction.print:
        await _printPendingUpload(upload);
        return;
      case _PendingMenuAction.sendToDesktop:
        await _sendPendingToDesktop(upload);
        return;
      case _PendingMenuAction.sendToChat:
        await _sendPendingToChat(upload);
        return;
      case _PendingMenuAction.share:
        await _sharePendingUpload(upload);
        return;
      case _PendingMenuAction.open:
        await OpenFilex.open(upload.filePath);
        return;
      case _PendingMenuAction.delete:
        await _deletePendingUpload(upload);
        return;
    }
  }

  Widget _buildMetaChip(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(BuildContext context, PendingUpload pendingUpload) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.primary.withValues(alpha: 0.1)
            : colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF1F5F9),
          ),
          left: BorderSide(color: colorScheme.primary, width: 4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    UploadSummaryScreen(pendingUpload: pendingUpload),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.phone_iphone_rounded,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pendingUpload.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.pages_outlined,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'محلي - ${pendingUpload.pageCount} صفحة',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.data_usage_rounded,
                            size: 14,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            formatFileSize(pendingUpload.fileSize),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_PendingMenuAction>(
                  icon: Icon(
                    Icons.more_horiz,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'الخيارات',
                  onSelected: (action) {
                    unawaited(_handlePendingMenuAction(action, pendingUpload));
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _PendingMenuAction.upload,
                      child: Text('رفع للسيرفر'),
                    ),
                    PopupMenuItem(
                      value: _PendingMenuAction.print,
                      child: Text('طباعة'),
                    ),
                    PopupMenuItem(
                      value: _PendingMenuAction.sendToDesktop,
                      child: Text('إرسال للكمبيوتر'),
                    ),
                    PopupMenuItem(
                      value: _PendingMenuAction.sendToChat,
                      child: Text('إرسال للشات'),
                    ),
                    PopupMenuItem(
                      value: _PendingMenuAction.share,
                      child: Text('مشاركة / حفظ في الهاتف'),
                    ),
                    PopupMenuItem(
                      value: _PendingMenuAction.open,
                      child: Text('فتح محليًا'),
                    ),
                    PopupMenuItem(
                      value: _PendingMenuAction.delete,
                      child: Text('حذف', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentCard(BuildContext context, RemoteDocument document) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () => _downloadAndOpen(document),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.picture_as_pdf_rounded,
                color: Color(0xFFDC2626),
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatDate(document.createdAt)} • ${formatFileSize(document.fileSize)} • ${document.pageCount} صفحة',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_DocumentMenuAction>(
              icon: Icon(
                Icons.more_horiz,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              tooltip: 'الخيارات',
              onSelected: (action) {
                unawaited(_handleDocumentMenuAction(action, document));
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _DocumentMenuAction.print,
                  child: Text('طباعة'),
                ),
                PopupMenuItem(
                  value: _DocumentMenuAction.sendToDesktop,
                  child: Text('إرسال للكمبيوتر'),
                ),
                PopupMenuItem(
                  value: _DocumentMenuAction.sendToChat,
                  child: Text('إرسال للشات'),
                ),
                PopupMenuItem(
                  value: _DocumentMenuAction.share,
                  child: Text('مشاركة / حفظ في الهاتف'),
                ),
                PopupMenuItem(
                  value: _DocumentMenuAction.rename,
                  child: Text('إعادة تسمية'),
                ),
                PopupMenuItem(
                  value: _DocumentMenuAction.delete,
                  child: Text('حذف', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documentsState = ref.watch(remoteDocumentsControllerProvider);
    final pendingState = ref.watch(pendingUploadsControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Future<void> refreshDocuments() async {
      await Future.wait([
        ref.read(remoteDocumentsControllerProvider.notifier).refresh(),
        ref.read(pendingUploadsControllerProvider.notifier).refresh(),
      ]);
    }

    final headerCard = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? colorScheme.surfaceContainer : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark
                ? colorScheme.outlineVariant.withValues(alpha: 0.4)
                : const Color(0xFFF1F5F9),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.05 : 0.02),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _sendLocalFileToDesktop,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.computer_rounded),
              label: const Text('إرسال ملف إلى الكمبيوتر'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _printLocalFileFromDevice,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('طباعة من الجهاز'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: refreshDocuments,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تحديث الملفات'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final banners = <Widget>[
      if (_isDownloading)
        AppDownloadProgressBanner(
          fileName: _downloadingFileName,
          progress: _downloadProgress,
        ),
      if (_isDownloading && DateTime.now().millisecondsSinceEpoch < 0)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'جاري تنزيل ${_downloadingFileName ?? 'الملف'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _downloadProgress),
            ],
          ),
        ),
      if (_isPrinting)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.print_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'جار إرسال ${_printingFileName ?? 'الملف'} للطباعة...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ),
        ),
      if (_isSendingToDesktop)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'إرسال ${_sendingFileName ?? 'الملف'} إلى الكمبيوتر',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _desktopSendProgress <= 0
                    ? null
                    : _desktopSendProgress.clamp(0, 1).toDouble(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _desktopSendStageMessage ?? 'جاري الإرسال...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(_desktopSendProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ],
          ),
        ),
      if (_isSendingToChat)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'جار إرسال ${_sendingChatFileName ?? 'الملف'} إلى الشات...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ),
        ),
    ];

    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark
              ? colorScheme.surfaceContainer
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? colorScheme.outlineVariant.withValues(alpha: 0.2)
                : const Color(0xFFE2E8F0),
          ),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'ابحث باسم الملف',
            hintStyle: TextStyle(
              color: isDark ? Colors.white54 : colorScheme.onSurfaceVariant,
            ),
            prefixIcon: Icon(Icons.search, color: colorScheme.primary),
            suffixIcon: _searchController.text.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'مسح',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('الملفات'),
        actions: [
          IconButton(
            tooltip: 'طباعة ملف من الجهاز',
            onPressed: _printLocalFileFromDevice,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            onPressed: refreshDocuments,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Builder(
            builder: (context) {
              final isLoading =
                  documentsState.isLoading || pendingState.isLoading;
              if (isLoading &&
                  documentsState.valueOrNull == null &&
                  pendingState.valueOrNull == null) {
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    headerCard,
                    ...banners,
                    searchField,
                    ...List.generate(
                      6,
                      (_) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShimmerSkeleton(width: 180, height: 14),
                                SizedBox(height: 10),
                                ShimmerSkeleton(width: 260, height: 12),
                                SizedBox(height: 8),
                                ShimmerSkeleton(width: 220, height: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (documentsState.hasError) {
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    headerCard,
                    ...banners,
                    searchField,
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(documentsState.error.toString()),
                      ),
                    ),
                  ],
                );
              }

              final remoteDocs = documentsState.valueOrNull ?? [];
              final pendingDocs = pendingState.valueOrNull ?? [];

              final filteredRemote = _filter(remoteDocs);
              final query = _searchController.text.trim().toLowerCase();
              final filteredPending = query.isEmpty
                  ? pendingDocs
                  : pendingDocs
                        .where(
                          (doc) => doc.fileName.toLowerCase().contains(query),
                        )
                        .toList();

              final merged = <dynamic>[...filteredPending, ...filteredRemote];
              merged.sort((a, b) {
                final aDate = a is PendingUpload
                    ? a.createdAt
                    : (a as RemoteDocument).createdAt;
                final bDate = b is PendingUpload
                    ? b.createdAt
                    : (b as RemoteDocument).createdAt;
                return bDate.compareTo(aDate);
              });

              return RefreshIndicator(
                onRefresh: refreshDocuments,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    headerCard,
                    ...banners,
                    searchField,
                    if (merged.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('لا توجد ملفات')),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: merged.map((doc) {
                              if (doc is PendingUpload) {
                                return _buildPendingCard(context, doc);
                              } else {
                                return _buildDocumentCard(
                                  context,
                                  doc as RemoteDocument,
                                );
                              }
                            }).toList(),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: OutlinedButton.icon(
                        onPressed: () => ref
                            .read(remoteDocumentsControllerProvider.notifier)
                            .loadMore(),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('تحميل المزيد'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_isSendingToDesktop)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.18),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.computer_rounded,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'إرسال ${_sendingFileName ?? 'الملف'} إلى الكمبيوتر',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              LinearProgressIndicator(
                                value: _desktopSendProgress <= 0
                                    ? null
                                    : _desktopSendProgress
                                          .clamp(0, 1)
                                          .toDouble(),
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _desktopSendStageMessage ??
                                          'جاري الإرسال...',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${(_desktopSendProgress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
