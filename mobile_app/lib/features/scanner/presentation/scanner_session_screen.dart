import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/document_paper_size.dart';
import '../../../shared/models/pending_upload.dart';
import '../../../shared/models/scan_page.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/services/remote_desktop_file_service.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../files/presentation/upload_summary_screen.dart';
import '../data/scanner_service.dart';

enum _PostScanAction { addPage, startNewFile, saveAndFinish }

class ScannerSessionScreen extends ConsumerStatefulWidget {
  const ScannerSessionScreen({super.key});

  @override
  ConsumerState<ScannerSessionScreen> createState() =>
      _ScannerSessionScreenState();
}

class _ScannerSessionScreenState extends ConsumerState<ScannerSessionScreen> {
  bool _autoStarted = false;
  bool _isSavingSession = false;
  bool _isLoadingScanner = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = ref.read(scanSessionControllerProvider).valueOrNull;
    if (!_autoStarted && (session == null || session.pages.isEmpty)) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
    }
  }

  Future<void> _startScan({String? replacePageId}) async {
    if (_isSavingSession || _isLoadingScanner) {
      return;
    }

    setState(() => _isLoadingScanner = true);

    final sessionController = ref.read(scanSessionControllerProvider.notifier);
    final scannerService = ref.read(scannerServiceProvider);

    await sessionController.ensureSession();
    if (!mounted) return;
    final session = ref.read(scanSessionControllerProvider).valueOrNull;
    if (session == null) {
      setState(() => _isLoadingScanner = false);
      return;
    }

    List<String>? newImages;
    try {
      newImages = await scannerService.scanMultiplePages();
    } on ScannerPermissionDeniedException catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingScanner = false);
      await _showScannerPermissionDialog(error);
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingScanner = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }

    if (mounted) {
      setState(() => _isLoadingScanner = false);
    }

    if (!mounted || newImages == null || newImages.isEmpty) return;

    for (int i = 0; i < newImages.length; i++) {
      final rawImagePath = newImages[i];
      final resolvedImagePath = await ref
          .read(localDocumentStoreProvider)
          .importRawScanFile(sessionId: session.id, sourcePath: rawImagePath);
      if (!mounted) return;

      final page = ScanPage(
        id: (i == 0 && replacePageId != null)
            ? replacePageId
            : DateTime.now().microsecondsSinceEpoch.toString() + i.toString(),
        imagePath: resolvedImagePath,
        createdAt: DateTime.now(),
      );

      if (i == 0 && replacePageId != null) {
        await sessionController.replacePage(replacePageId, page);
      } else {
        await sessionController.addPage(page);
      }
    }
  }

  Future<void> _showScannerPermissionDialog(
    ScannerPermissionDeniedException error,
  ) {
    final isPermanent = error.permanentlyDenied;
    final platformName = Platform.isIOS ? 'iOS' : 'أندرويد';
    final deviceName = Platform.isIOS ? 'iPhone' : 'الهاتف';
    final palette = context.appThemePalette;

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.danger.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.photo_camera_front_rounded,
            color: palette.danger,
            size: 40,
          ),
        ),
        title: const Text(
          'الصلاحية مطلوبة للمسح',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isPermanent
                  ? 'المسح الضوئي يحتاج إذن الوصول إلى الكاميرا (${error.permission}).\n\nتم رفض الإذن سابقاً من إعدادات نظام $platformName، يرجى فتح الإعدادات وتفعيله يدوياً.'
                  : 'يحتاج التطبيق إلى إذن الوصول إلى الكاميرا (${error.permission}) لتتمكن من مسح الصفحات والمستندات واستيرادها بنجاح.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(110, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('إلغاء'),
          ),
          if (isPermanent)
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(140, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('فتح الإعدادات'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                minimumSize: const Size(120, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('موافق'),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomSheetOption({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(
                alpha: isDark ? 0.3 : 0.6,
              ),
            ),
            color: isDark ? theme.colorScheme.surfaceContainer : Colors.white,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<_PostScanAction?> _showPostScanSheet() {
    final palette = context.appThemePalette;

    return showModalBottomSheet<_PostScanAction>(
      isScrollControlled: true,
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text(
                'ما الخطوة التالية للمستند؟',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 18),
              _buildBottomSheetOption(
                context: context,
                icon: Icons.add_photo_alternate_rounded,
                iconColor: palette.accent,
                iconBgColor: palette.accent.withValues(alpha: 0.12),
                title: 'إضافة صفحة لنفس الملف',
                subtitle: 'التقط صفحة إضافية وألحقها بالملف الحالي',
                onTap: () => Navigator.pop(context, _PostScanAction.addPage),
              ),
              const SizedBox(height: 12),
              _buildBottomSheetOption(
                context: context,
                icon: Icons.check_circle_rounded,
                iconColor: palette.success,
                iconBgColor: palette.success.withValues(alpha: 0.12),
                title: 'حفظ المستند الحالي وإنهاء',
                subtitle: 'حفظ الصفحات الممسوحة كملف PDF وإنهاء الجلسة',
                onTap: () =>
                    Navigator.pop(context, _PostScanAction.saveAndFinish),
              ),
              const SizedBox(height: 12),
              _buildBottomSheetOption(
                context: context,
                icon: Icons.library_add_rounded,
                iconColor: palette.warning,
                iconBgColor: palette.warning.withValues(alpha: 0.12),
                title: 'حفظ وبدء ملف جديد',
                subtitle: 'حفظ الملف الحالي والبدء فوراً بمسح مستند آخر',
                onTap: () =>
                    Navigator.pop(context, _PostScanAction.startNewFile),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _generatedDefaultFileName() {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    final ownerName = authUser == null
        ? null
        : (authUser.fullName.trim().isNotEmpty
              ? authUser.fullName
              : authUser.username);
    return defaultPdfName(ownerName: ownerName);
  }

  Future<({String name, bool applyEnhancement})?> _askFileName() async {
    final controller = TextEditingController(text: _generatedDefaultFileName());
    final palette = context.appThemePalette;
    bool applyEnhancement = false;

    return showDialog<({String name, bool applyEnhancement})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.picture_as_pdf_rounded,
              color: palette.accent,
              size: 40,
            ),
          ),
          title: const Text(
            'حفظ ملف PDF جديد',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أدخل اسماً للمستند. حدّد نوع الورقة لكل صفحة من قائمة الصفحات قبل الحفظ:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'اسم الملف',
                    hintText: 'مثال: مستند ممسوح',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: applyEnhancement,
                  onChanged: (val) =>
                      setDialogState(() => applyEnhancement = val),
                  title: const Text('تفعيل التحسين الاحترافي'),
                  subtitle: const Text(
                    'إزالة الظلال وتوضيح النصوص (قد يبطئ الحفظ)',
                    style: TextStyle(fontSize: 11),
                  ),
                  contentPadding: EdgeInsets.zero,
                  activeColor: palette.accent,
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final val = controller.text.trim();
                Navigator.pop(
                  context,
                  val.isNotEmpty
                      ? (name: val, applyEnhancement: applyEnhancement)
                      : null,
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(120, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('متابعة وحفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndFinish() async {
    if (_isSavingSession) {
      return;
    }

    final preferences = ref.read(userPreferencesControllerProvider).valueOrNull;
    final autoSave = preferences?.autoSaveAfterScan == true;
    final input = autoSave
        ? (name: _generatedDefaultFileName(), applyEnhancement: false)
        : await _askFileName();
    if (input == null || input.name.isEmpty || !mounted) return;

    try {
      setState(() {
        _isSavingSession = true;
      });
      final sessionController = ref.read(
        scanSessionControllerProvider.notifier,
      );
      final pendingController = ref.read(
        pendingUploadsControllerProvider.notifier,
      );
      final pending = await sessionController.saveCurrentSession(
        input.name,
        saveDirectoryPath: preferences?.scanSaveDirectoryPath,
        applyEnhancement: input.applyEnhancement,
      );
      if (!mounted) return;
      await pendingController.refresh();
      if (!mounted) return;
      final shouldAutoSaveToDesktop = await _shouldAutoSaveToDesktop();
      if (shouldAutoSaveToDesktop) {
        final sent = await _sendPendingToDesktop(
          pending,
          source: 'mobile_scan_save_and_finish',
        );
        if (sent && mounted) {
          Navigator.of(context).pop();
          return;
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => UploadSummaryScreen(pendingUpload: pending),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_scannerFriendlyErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSession = false;
        });
      }
    }
  }

  Future<void> _saveCurrentAndStartNew() async {
    if (_isSavingSession) {
      return;
    }

    final preferences = ref.read(userPreferencesControllerProvider).valueOrNull;
    final autoSave = preferences?.autoSaveAfterScan == true;
    final input = autoSave
        ? (name: _generatedDefaultFileName(), applyEnhancement: false)
        : await _askFileName();
    if (input == null || input.name.isEmpty || !mounted) return;

    try {
      setState(() {
        _isSavingSession = true;
      });
      final sessionController = ref.read(
        scanSessionControllerProvider.notifier,
      );
      final pendingController = ref.read(
        pendingUploadsControllerProvider.notifier,
      );
      final pending = await sessionController.saveCurrentSession(
        input.name,
        saveDirectoryPath: preferences?.scanSaveDirectoryPath,
        applyEnhancement: input.applyEnhancement,
      );
      if (!mounted) return;
      await pendingController.refresh();
      if (!mounted) return;
      final shouldAutoSaveToDesktop = await _shouldAutoSaveToDesktop();
      if (shouldAutoSaveToDesktop) {
        final sent = await _sendPendingToDesktop(
          pending,
          source: 'mobile_scan_save_and_start_new',
        );
        if (!mounted) return;
        if (sent) {
          await sessionController.startNewEmptySession();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حفظ الملف مباشرة على الكمبيوتر وبدأ ملف جديد'),
            ),
          );
          await _startScan();
          return;
        }
      }
      if (!mounted) return;
      await sessionController.startNewEmptySession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الملف الحالي وبدء ملف جديد')),
      );
      await _startScan();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_scannerFriendlyErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSession = false;
        });
      }
    }
  }

  String _scannerFriendlyErrorMessage(Object error) {
    final rawMessage = error.toString().trim();
    final normalized = rawMessage.toLowerCase();
    if (normalized.contains('pathaccessexception') ||
        normalized.contains('operation not permitted') ||
        normalized.contains('errno = 1')) {
      return 'تعذر الحفظ في المجلد المحدد على الهاتف. تم تجهيز النظام لاستخدام مجلد التطبيق الآمن بدلًا منه. جرّب الحفظ مرة أخرى.';
    }
    if (rawMessage.startsWith('Exception: ')) {
      return rawMessage.substring('Exception: '.length).trim();
    }
    return rawMessage.isEmpty
        ? 'تعذر حفظ الملف حاليًا. حاول مرة أخرى.'
        : rawMessage;
  }

  Future<bool> _shouldAutoSaveToDesktop() async {
    try {
      final status = await ref
          .read(remoteDesktopFileServiceProvider)
          .fetchStatus();
      return status.hasDesktop && status.autoSaveAfterScan;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendPendingToDesktop(
    PendingUpload pending, {
    required String source,
  }) async {
    final authUser = ref.read(authControllerProvider).valueOrNull;
    final maxInlineBytes = authUser?.role == 'admin'
        ? kAdminInlineFileSaveBytes
        : kMaxInlineFileSaveBytes;
    final result = await ref
        .read(remoteDesktopFileServiceProvider)
        .requestSaveFromLocalFile(
          filePath: pending.filePath,
          fileName: pending.fileName,
          mimeType: 'application/pdf',
          source: source,
          maxInlineFileBytes: maxInlineBytes,
        );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }

    if (!result.success) {
      return false;
    }

    await ref
        .read(pendingUploadsControllerProvider.notifier)
        .removeById(pending.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(scanSessionControllerProvider);
    final pages = sessionState.valueOrNull?.pages ?? const <ScanPage>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.appThemePalette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مسح مستند جديد'),
        actions: [
          if (pages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton(
                onPressed: _isSavingSession ? null : _saveAndFinish,
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                child: const Text('حفظ وإنهاء'),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSavingSession ? null : _startScan,
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.camera_alt_rounded),
        label: Text(
          pages.isEmpty ? 'التقاط الصفحة الأولى' : 'إضافة صفحة',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: Stack(
        children: [
          sessionState.when(
            loading: () => ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                ShimmerSkeleton(height: 86, borderRadius: 16),
                SizedBox(height: 12),
                Row(
                  children: [
                    ShimmerSkeleton(width: 86, height: 124, borderRadius: 14),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          ShimmerSkeleton(height: 14, borderRadius: 8),
                          SizedBox(height: 8),
                          SizedBox(
                            width: 180,
                            child: ShimmerSkeleton(height: 12, borderRadius: 8),
                          ),
                          SizedBox(height: 10),
                          ShimmerSkeleton(height: 34, borderRadius: 10),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                ShimmerSkeleton(height: 130, borderRadius: 16),
                SizedBox(height: 12),
                ShimmerSkeleton(height: 130, borderRadius: 16),
              ],
            ),
            error: (error, stackTrace) => Center(child: Text(error.toString())),
            data: (_) {
              if (pages.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                palette.accent.withValues(alpha: 0.16),
                                palette.accent.withValues(alpha: 0.02),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh
                                    : Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: palette.accent.withValues(
                                      alpha: 0.1,
                                    ),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                                border: Border.all(
                                  color: palette.accent.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.document_scanner_rounded,
                                size: 44,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'جاهز للمسح الضوئي',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            'ابدأ بمسح أول صفحة. بعد التقاط كل صفحة، يمكنك تدويرها أو إعادة مسحها أو ترتيب الصفحات كما يحلو لك.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withValues(alpha: 0.7),
                                  height: 1.5,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? Theme.of(context).colorScheme.surfaceContainer
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant
                              .withValues(alpha: isDark ? 0.3 : 0.6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.15 : 0.03,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.pages_rounded,
                                color: palette.accent,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'عدد الصفحات: ${pages.length}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'اضغط واسحب الصفحات لإعادة ترتيبها',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.color
                                              ?.withValues(alpha: 0.65),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed: _isSavingSession
                                  ? null
                                  : _saveAndFinish,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(80, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('حفظ'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: pages.length,
                      onReorder: _isSavingSession
                          ? (_, _) {}
                          : (oldIndex, newIndex) => ref
                                .read(scanSessionControllerProvider.notifier)
                                .reorderPages(oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final page = pages[index];
                        return Card(
                          key: ValueKey(page.id),
                          color: isDark
                              ? Theme.of(context).colorScheme.surfaceContainer
                              : Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: isDark ? 0.3 : 0.6),
                            ),
                          ),
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(alpha: 0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(11),
                                    child: Image.file(
                                      File(page.imagePath),
                                      key: ValueKey(
                                        File(page.imagePath).existsSync()
                                            ? File(page.imagePath)
                                                  .lastModifiedSync()
                                                  .millisecondsSinceEpoch
                                            : 0,
                                      ),
                                      width: 86,
                                      height: 114,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'الصفحة ${index + 1}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.schedule_rounded,
                                            size: 14,
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color
                                                ?.withValues(alpha: 0.6),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            formatDate(page.createdAt),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.color
                                                      ?.withValues(alpha: 0.7),
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      DropdownButtonFormField<
                                        DocumentPaperSize
                                      >(
                                        value: page.paperSize,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          labelText: 'نوع الورقة',
                                          prefixIcon: Icon(
                                            Icons.aspect_ratio_rounded,
                                            size: 18,
                                            color: palette.accent,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 8,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          isDense: true,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                        items: DocumentPaperSize.values
                                            .map(
                                              (size) => DropdownMenuItem(
                                                value: size,
                                                child: Text(size.label),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: _isSavingSession
                                            ? null
                                            : (size) {
                                                if (size == null) return;
                                                ref
                                                    .read(
                                                      scanSessionControllerProvider
                                                          .notifier,
                                                    )
                                                    .updatePagePaperSize(
                                                      page.id,
                                                      size,
                                                    );
                                              },
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _isSavingSession
                                                ? null
                                                : () => ref
                                                      .read(
                                                        scanSessionControllerProvider
                                                            .notifier,
                                                      )
                                                      .rotatePage(page.id),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: palette.accent,
                                              side: BorderSide(
                                                color: palette.accent
                                                    .withValues(alpha: 0.4),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              minimumSize: const Size(0, 34),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.rotate_right_rounded,
                                              size: 15,
                                            ),
                                            label: const Text('تدوير'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _isSavingSession
                                                ? null
                                                : () => _startScan(
                                                    replacePageId: page.id,
                                                  ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withValues(alpha: 0.8),
                                              side: BorderSide(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.outlineVariant,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              minimumSize: const Size(0, 34),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.cached_rounded,
                                              size: 15,
                                            ),
                                            label: const Text('إعادة مسح'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _isSavingSession
                                                ? null
                                                : () => ref
                                                      .read(
                                                        scanSessionControllerProvider
                                                            .notifier,
                                                      )
                                                      .deletePage(page.id),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: palette.danger,
                                              side: BorderSide(
                                                color: palette.danger
                                                    .withValues(alpha: 0.4),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              minimumSize: const Size(0, 34),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 15,
                                            ),
                                            label: const Text('حذف'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          if (_isSavingSession)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          elevation: 8,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 4.5,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'جارٍ تجهيز الملف وحفظه...',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'انتظر لحظات حتى ينتهي إنشاء الملف بدون إغلاق الشاشة.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withValues(alpha: 0.75),
                                        height: 1.4,
                                      ),
                                  textAlign: TextAlign.center,
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
            ),
          if (_isLoadingScanner)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: palette.accent),
                        const SizedBox(height: 16),
                        const Text(
                          'جارٍ تحميل الكاميرا...',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
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
