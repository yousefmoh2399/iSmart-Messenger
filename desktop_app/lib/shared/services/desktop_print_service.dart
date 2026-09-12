import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/media_url_resolver.dart';
import '../../features/auth/data/auth_repository.dart';
import 'web_platform_bridge.dart' as web_bridge;

import 'print_job_processor.dart';

class PrinterCatalog {
  const PrinterCatalog({required this.printers, required this.defaultPrinter});

  final List<String> printers;
  final String? defaultPrinter;
}

class DesktopPrintResult {
  DesktopPrintResult({
    required this.success,
    required this.message,
    required this.printerName,
  });

  final bool success;
  final String message;
  final String? printerName;
}

class DesktopPrintService implements PrintExecutor {
  DesktopPrintService({
    required ApiClient apiClient,
    required AuthRepository authRepository,
  }) : _apiClient = apiClient,
       _authRepository = authRepository;

  final ApiClient _apiClient;
  final AuthRepository _authRepository;

  void _log(String msg) {
    try {
      File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}cs_print_log.txt',
      ).writeAsStringSync(
        '${DateTime.now().toIso8601String()}: $msg\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  String _describePrintPayload(Map<String, dynamic> payload) {
    final inline = payload['inlineFileBase64']?.toString().trim();
    final token = payload['requestAuthToken']?.toString().trim();
    return 'jobId=${payload['jobId']}, '
        'fileName=${payload['fileName']}, '
        'mimeType=${payload['mimeType']}, '
        'downloadUrl=${_redactUrl(payload['downloadUrl']?.toString())}, '
        'hasInlineFile=${inline != null && inline.isNotEmpty}, '
        'hasRequestAuthToken=${token != null && token.isNotEmpty}, '
        'preferredPrinterName=${payload['preferredPrinterName']}';
  }

  String _redactUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null) {
      return '<invalid-url>';
    }
    final safe = parsed.replace(query: parsed.hasQuery ? '<redacted>' : null);
    return safe.toString();
  }

  Future<PrinterCatalog> getPrinterCatalog() async {
    if (kIsWeb) {
      if (web_bridge.isElectron()) {
        final printerEntries = await web_bridge.getElectronPrinters();
        final printers =
            printerEntries
                .map((entry) => entry['name']?.toString().trim() ?? '')
                .where((entry) => entry.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        String? defaultPrinter;
        for (final entry in printerEntries) {
          if (entry['isDefault'] == true) {
            defaultPrinter = entry['name']?.toString().trim();
            break;
          }
        }
        return PrinterCatalog(
          printers: printers,
          defaultPrinter: defaultPrinter?.isNotEmpty == true
              ? defaultPrinter
              : null,
        );
      }
      return const PrinterCatalog(
        printers: <String>['طابعة المتصفح'],
        defaultPrinter: 'طابعة المتصفح',
      );
    }
    final printers = await _listPrinters();
    final defaultPrinter = await _getDefaultPrinter();
    return PrinterCatalog(printers: printers, defaultPrinter: defaultPrinter);
  }

  @override
  Future<DesktopPrintResult> executePrintJob(
    Map<String, dynamic> payload, {
    String? preferredPrinterName,
  }) async {
    _log('executePrintJob called with ${_describePrintPayload(payload)}');
    final fileName = (payload['fileName']?.toString().trim().isNotEmpty == true)
        ? payload['fileName'].toString().trim()
        : 'print_file';
    final mimeType = payload['mimeType']?.toString().trim();
    final explicitPrinter = payload['preferredPrinterName']?.toString().trim();
    final printerName = _normalizeOptional(
      preferredPrinterName,
      fallback: explicitPrinter,
    );

    if (kIsWeb) {
      return _executeWebPrintJob(
        payload,
        fileName: fileName,
        mimeType: mimeType,
        printerName: printerName,
        requestAuthToken: payload['requestAuthToken']?.toString(),
        jobId: payload['jobId']?.toString(),
        disableAdobeFallback: payload['disableAdobeFallback'] == true,
      );
    }

    final String localPath;
    try {
      localPath = await _resolvePrintableFile(
        fileName: fileName,
        mimeType: mimeType,
        downloadUrl: payload['downloadUrl']?.toString(),
        inlineFileBase64: payload['inlineFileBase64']?.toString(),
        requestAuthToken: payload['requestAuthToken']?.toString(),
      );
    } catch (error) {
      return DesktopPrintResult(
        success: false,
        message: error.toString(),
        printerName: printerName,
      );
    }

    try {
      final result = await _sendToPrinter(localPath, printerName);
      if (result.$1) {
        return DesktopPrintResult(
          success: true,
          message: 'تم إرسال الملف للطباعة بنجاح.',
          printerName: printerName,
        );
      }
      return DesktopPrintResult(
        success: false,
        message: result.$2 ?? 'تعذر إرسال الملف للطباعة.',
        printerName: printerName,
      );
    } catch (error) {
      return DesktopPrintResult(
        success: false,
        message: error.toString(),
        printerName: printerName,
      );
    }
  }

  Future<DesktopPrintResult> _executeWebPrintJob(
    Map<String, dynamic> payload, {
    required String fileName,
    required String? mimeType,
    required String? printerName,
    String? requestAuthToken,
    String? jobId,
    bool? disableAdobeFallback,
  }) async {
    try {
      final inlineData = payload['inlineFileBase64']?.toString().trim() ?? '';
      if (inlineData.isNotEmpty) {
        await web_bridge.printBytes(
          bytes: base64Decode(inlineData),
          fileName: fileName,
          mimeType: mimeType,
          printerName: printerName,
          jobId: jobId,
          disableAdobeFallback: disableAdobeFallback,
        );
      } else {
        final downloadUrl = payload['downloadUrl']?.toString().trim() ?? '';
        if (downloadUrl.isEmpty) {
          return DesktopPrintResult(
            success: false,
            message: 'No printable file was provided.',
            printerName: printerName,
          );
        }
        final token = requestAuthToken?.trim();
        if (web_bridge.isElectron() && token != null && token.isNotEmpty) {
          final bytes = await web_bridge.fetchElectronBytes(
            url: _normalizeDownloadUrl(downloadUrl),
            headers: {'Authorization': 'Bearer $token'},
          );

          try {
            final text = utf8.decode(bytes);
            if (text.contains('انتهت صلاحية الجلسة') ||
                text.contains('"error"')) {
              throw Exception(
                'انتهت صلاحية الجلسة أو فشل التحقق. الخادم رفض الطلب.',
              );
            }
          } on FormatException {
            // Ignore format exception, means it's a valid binary file (e.g. PDF/Image)
          }

          await web_bridge.printBytes(
            bytes: bytes,
            fileName: fileName,
            mimeType: mimeType,
            printerName: printerName,
            jobId: jobId,
            disableAdobeFallback: disableAdobeFallback,
          );
        } else {
          await web_bridge.printUrl(
            _normalizeDownloadUrl(downloadUrl),
            printerName: printerName,
            jobId: jobId,
            disableAdobeFallback: disableAdobeFallback,
          );
        }
      }
      return DesktopPrintResult(
        success: true,
        message: 'تم فتح نافذة الطباعة في المتصفح.',
        printerName: printerName ?? 'طابعة المتصفح',
      );
    } catch (error) {
      return DesktopPrintResult(
        success: false,
        message: error.toString(),
        printerName: printerName,
      );
    }
  }

  String? _normalizeOptional(String? value, {String? fallback}) {
    final first = value?.trim();
    if (first != null && first.isNotEmpty) {
      return first;
    }
    final second = fallback?.trim();
    if (second != null && second.isNotEmpty) {
      return second;
    }
    return null;
  }

  Future<String> _resolvePrintableFile({
    required String fileName,
    required String? mimeType,
    required String? downloadUrl,
    required String? inlineFileBase64,
    String? requestAuthToken,
  }) async {
    _log(
      '_resolvePrintableFile called: fileName=$fileName, downloadUrl=${_redactUrl(downloadUrl)}, inline=${inlineFileBase64 != null}',
    );
    final tempDir = await getTemporaryDirectory();
    final safeName = _sanitizeFileName(
      fileName,
      mimeType,
      downloadUrl: downloadUrl,
    );
    final uniqueId = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      p.join(tempDir.path, 'print_jobs', '${uniqueId}_$safeName'),
    );
    await file.parent.create(recursive: true);
    final outputPath = file.path;

    final inlineData = inlineFileBase64?.trim() ?? '';
    if (inlineData.isNotEmpty) {
      _log('Using inlineFileBase64 data');
      final bytes = base64Decode(inlineData);
      if (bytes.isEmpty) {
        throw Exception('Printable file is empty.');
      }

      try {
        final text = utf8.decode(bytes);
        if (text.contains('انتهت صلاحية الجلسة') ||
            text.contains('"error"') ||
            text.contains('"message"')) {
          _log('Inline file data contains error JSON!');
          try {
            final json = jsonDecode(text) as Map<String, dynamic>;
            final msg =
                json['message']?.toString() ?? json['error']?.toString();
            if (msg != null && msg.isNotEmpty) {
              throw Exception(msg);
            }
          } catch (_) {}

          throw Exception(
            'الملف المرفق يحتوي على رسالة خطأ بدلاً من المحتوى المطلوب.',
          );
        }
      } on FormatException {
        // Binary PDFs/images are not expected to decode as UTF-8.
      } catch (e) {
        if (e is Exception) rethrow;
      }

      await File(outputPath).writeAsBytes(bytes, flush: true);
      return outputPath;
    }

    final url = downloadUrl?.trim() ?? '';
    if (url.isEmpty) {
      throw Exception('ملف الطباعة غير متاح.');
    }

    await _downloadFile(
      url: url,
      outputPath: outputPath,
      requestAuthToken: requestAuthToken,
    );
    return outputPath;
  }

  String _sanitizeFileName(
    String input,
    String? mimeType, {
    String? downloadUrl,
  }) {
    final cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isNotEmpty && p.extension(cleaned).isNotEmpty) {
      return cleaned;
    }
    final fallbackExt = _resolveFallbackExtension(
      mimeType: mimeType,
      downloadUrl: downloadUrl,
    );
    final stem = cleaned.isEmpty ? 'print_file' : cleaned;
    return '$stem$fallbackExt';
  }

  String _resolveFallbackExtension({
    required String? mimeType,
    required String? downloadUrl,
  }) {
    final byMime = switch ((mimeType ?? '').toLowerCase()) {
      'application/pdf' => '.pdf',
      _ when (mimeType ?? '').toLowerCase().startsWith('image/') => '.jpg',
      _ => '',
    };
    if (byMime.isNotEmpty) {
      return byMime;
    }

    final byUrl = _extensionFromUrl(downloadUrl);
    if (byUrl != null) {
      return byUrl;
    }

    // Avoid .bin because it usually has no print association on Windows.
    return '.pdf';
  }

  String? _extensionFromUrl(String? url) {
    final value = url?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return null;
    }
    final ext = p.extension(uri.path).toLowerCase();
    if (ext.isEmpty || ext == '.') {
      return null;
    }
    if (!RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext)) {
      return null;
    }
    return ext;
  }

  Future<void> _downloadFile({
    required String url,
    required String outputPath,
    String? requestAuthToken,
  }) async {
    _log(
      '_downloadFile started: url=${_redactUrl(url)}, outputFile=${p.basename(outputPath)}',
    );
    final payloadToken = requestAuthToken?.trim();
    final token = payloadToken != null && payloadToken.isNotEmpty
        ? payloadToken
        : await _authRepository.getValidToken();
    _log('Token valid: ${token != null && token.isNotEmpty}');
    final normalizedUrl = _normalizeDownloadUrl(url);
    _log('Normalized URL: ${_redactUrl(normalizedUrl)}');

    final response = await _apiClient.dio.get<List<int>>(
      normalizedUrl,
      options: Options(
        headers: token == null || token.isEmpty
            ? null
            : {'Authorization': 'Bearer $token'},
        responseType: ResponseType.bytes,
        validateStatus: (status) => true,
      ),
    );

    _log('Download response status: ${response.statusCode}');

    if (response.statusCode != null && response.statusCode! >= 400) {
      final contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      _log(
        'Download failed. Status: ${response.statusCode}, Content-Type: $contentType',
      );

      if (contentType.toLowerCase().contains('application/json') ||
          contentType.toLowerCase().contains('text/plain')) {
        try {
          final text = utf8.decode(response.data ?? <int>[]);
          _log('Error response received as text/json.');

          if (response.statusCode == 401 ||
              text.contains('انتهت صلاحية الجلسة')) {
            throw Exception(
              'انتهت صلاحية الجلسة أو فشل التحقق. الخادم رفض الطلب.',
            );
          }

          try {
            final json = jsonDecode(text) as Map<String, dynamic>;
            final msg =
                json['message']?.toString() ?? json['error']?.toString();
            if (msg != null && msg.isNotEmpty) {
              throw Exception(msg);
            }
          } catch (_) {}
        } catch (e) {
          if (e is Exception) rethrow;
        }
      }
      throw Exception(
        'الخادم أرجع خطأ ${response.statusCode} أثناء تنزيل الملف.',
      );
    }

    final contentType = response.headers.value(Headers.contentTypeHeader) ?? '';
    if (contentType.toLowerCase().contains('application/json')) {
      try {
        final text = utf8.decode(response.data ?? <int>[]);
        _log('Unexpected JSON response received instead of printable bytes.');

        if (text.contains('انتهت صلاحية الجلسة')) {
          throw Exception(
            'انتهت صلاحية الجلسة أو فشل التحقق. الخادم رفض الطلب.',
          );
        }

        try {
          final json = jsonDecode(text) as Map<String, dynamic>;
          final msg = json['message']?.toString() ?? json['error']?.toString();
          if (msg != null && msg.isNotEmpty) {
            throw Exception(msg);
          }
        } catch (_) {}

        throw Exception('الخادم أرجع خطأ بدلاً من الملف.');
      } catch (e) {
        if (e is Exception) rethrow;
      }
    }

    final bytes = Uint8List.fromList(response.data ?? const <int>[]);
    _log('File downloaded successfully, size: ${bytes.length}');
    await File(outputPath).writeAsBytes(bytes, flush: true);
  }

  String _normalizeDownloadUrl(String url) {
    final resolved = resolveApiUrl(url);
    final parsed = Uri.tryParse(resolved);
    if (parsed == null) {
      return resolved;
    }
    if (parsed.hasScheme && parsed.hasAuthority) {
      return parsed.toString();
    }
    final base = _apiClient.dio.options.baseUrl;
    return Uri.parse(base).resolveUri(parsed).toString();
  }

  Future<(bool, String?)> _sendToPrinter(
    String filePath,
    String? printerName,
  ) async {
    _log('_sendToPrinter called: filePath=$filePath, printerName=$printerName');
    if (Platform.isLinux || Platform.isMacOS) {
      final args = <String>[
        if (printerName != null && printerName.isNotEmpty) ...[
          '-d',
          printerName,
        ],
        filePath,
      ];
      final lp = await Process.run('lp', args);
      if (lp.exitCode == 0) {
        return (true, null);
      }

      final lprArgs = <String>[
        if (printerName != null && printerName.isNotEmpty) ...[
          '-P',
          printerName,
        ],
        filePath,
      ];
      final lpr = await Process.run('lpr', lprArgs);
      if (lpr.exitCode == 0) {
        return (true, null);
      }

      final message = (lp.stderr?.toString().trim().isNotEmpty == true)
          ? lp.stderr.toString().trim()
          : lpr.stderr.toString().trim();
      return (false, message.isEmpty ? 'فشل أمر الطباعة.' : message);
    }

    if (Platform.isWindows) {
      final ext = p.extension(filePath).toLowerCase();
      if (ext == '.pdf') {
        return _tryPrintPdfWithKnownTools(
          filePath: filePath,
          printerName: printerName,
        );
      }

      final command = '''
\$ErrorActionPreference = 'Stop'
\$filePath = \$env:PRINT_FILE_PATH
\$printerName = \$env:PRINT_PRINTER_NAME

if (-not (Test-Path -LiteralPath \$filePath)) {
  throw "Print file not found: \$filePath"
}

try {
  if ([string]::IsNullOrWhiteSpace(\$printerName)) {
    Start-Process -FilePath \$filePath -Verb Print -ErrorAction Stop | Out-Null
  } else {
    Start-Process -FilePath \$filePath -Verb PrintTo -ArgumentList \$printerName -ErrorAction Stop | Out-Null
  }
  exit 0
} catch {
  # Fallback for image files when shell print association is missing.
  if (\$filePath -match '\\.(png|jpg|jpeg|bmp|gif|tif|tiff)\$' -and (Get-Command mspaint.exe -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace(\$printerName)) {
      & mspaint.exe /p \$filePath | Out-Null
    } else {
      & mspaint.exe /pt \$filePath \$printerName | Out-Null
    }
    if (\$LASTEXITCODE -eq 0) {
      exit 0
    }
  }
  throw
}
''';

      final ps = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', command],
        environment: {
          'PRINT_FILE_PATH': filePath,
          'PRINT_PRINTER_NAME': printerName ?? '',
        },
      );
      if (ps.exitCode == 0) {
        return (true, null);
      }

      final message = ps.stderr.toString().trim();
      final normalized = message.toLowerCase();
      if (normalized.contains('no application is associated') ||
          normalized.contains('this operation')) {
        final pdfFallback = await _tryPrintPdfWithKnownTools(
          filePath: filePath,
          printerName: printerName,
        );
        if (pdfFallback.$1) {
          return (true, null);
        }
        if ((pdfFallback.$2 ?? '').isNotEmpty) {
          return (false, pdfFallback.$2);
        }
        return (
          false,
          'لا يوجد تطبيق افتراضي للطباعة لهذا النوع من الملفات على ويندوز. اضبط برنامج افتراضي (PDF/صور) أو ثبّت SumatraPDF ثم أعد المحاولة.',
        );
      }

      return (false, message.isEmpty ? 'فشل أمر الطباعة.' : message);
    }

    return (false, 'نظام التشغيل الحالي غير مدعوم للطباعة.');
  }

  Future<(bool, String?)> _tryPrintPdfWithKnownTools({
    required String filePath,
    required String? printerName,
  }) async {
    final ext = p.extension(filePath).toLowerCase();
    if (ext != '.pdf') {
      return (false, null);
    }

    final sumatraExe = await _findSumatraExe();
    if (sumatraExe != null) {
      final defaultPrinter = await _getDefaultPrinter();
      final isDefault =
          (printerName == null) ||
          (printerName.isEmpty) ||
          (printerName.trim().toLowerCase() ==
              defaultPrinter?.trim().toLowerCase());

      final args = <String>[
        '-silent',
        '-print-settings',
        'fit',
        if (!isDefault) ...['-print-to', printerName] else '-print-to-default',
        filePath,
      ];
      final result = await Process.run(sumatraExe, args);
      if (result.exitCode == 0) {
        return (true, null);
      }
    }

    final acrobatExe = await _findAcrobatExe();
    if (acrobatExe != null) {
      final defaultPrinter = printerName ?? await _getDefaultPrinter();
      if (defaultPrinter != null && defaultPrinter.isNotEmpty) {
        final args = <String>['/s', '/o', '/h', '/t', filePath, defaultPrinter];
        final result = await Process.run(acrobatExe, args);
        if (result.exitCode == 0) {
          return (true, null);
        }
      }
    }

    return (
      false,
      'تعذر طباعة PDF تلقائيًا. ثبّت SumatraPDF أو عيّن برنامج PDF افتراضي.',
    );
  }

  Future<String?> _findSumatraExe() async {
    final exeFromPath = await _findExecutableOnPath('SumatraPDF.exe');
    if (exeFromPath != null) {
      return exeFromPath;
    }

    final candidates = <String>[
      if ((Platform.environment['ProgramFiles'] ?? '').isNotEmpty)
        p.join(
          Platform.environment['ProgramFiles']!,
          'SumatraPDF',
          'SumatraPDF.exe',
        ),
      if ((Platform.environment['ProgramFiles(x86)'] ?? '').isNotEmpty)
        p.join(
          Platform.environment['ProgramFiles(x86)']!,
          'SumatraPDF',
          'SumatraPDF.exe',
        ),
      if ((Platform.environment['LocalAppData'] ?? '').isNotEmpty)
        p.join(
          Platform.environment['LocalAppData']!,
          'SumatraPDF',
          'SumatraPDF.exe',
        ),
    ];

    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  Future<String?> _findAcrobatExe() async {
    final exeFromPath = await _findExecutableOnPath('AcroRd32.exe');
    if (exeFromPath != null) {
      return exeFromPath;
    }

    final candidates = <String>[
      if ((Platform.environment['ProgramFiles'] ?? '').isNotEmpty)
        p.join(
          Platform.environment['ProgramFiles']!,
          'Adobe',
          'Acrobat Reader DC',
          'Reader',
          'AcroRd32.exe',
        ),
      if ((Platform.environment['ProgramFiles(x86)'] ?? '').isNotEmpty)
        p.join(
          Platform.environment['ProgramFiles(x86)']!,
          'Adobe',
          'Acrobat Reader DC',
          'Reader',
          'AcroRd32.exe',
        ),
    ];

    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  Future<String?> _findExecutableOnPath(String executableName) async {
    final result = await Process.run('where', [executableName]);
    if (result.exitCode != 0) {
      return null;
    }
    final lines = result.stdout
        .toString()
        .split('\n')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty);
    for (final path in lines) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  Future<List<String>> _listPrinters() async {
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('lpstat', ['-a']);
      if (result.exitCode != 0) {
        return const <String>[];
      }
      final lines = result.stdout.toString().split('\n');
      return lines
          .map((line) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) {
              return '';
            }
            return trimmed.split(RegExp(r'\s+')).first;
          })
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
    }

    if (Platform.isWindows) {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-CimInstance Win32_Printer | Select-Object Name | ConvertTo-Json -Compress',
      ]);
      if (result.exitCode != 0) {
        return const <String>[];
      }
      final raw = result.stdout.toString().trim();
      if (raw.isEmpty) {
        return const <String>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((entry) => entry['Name']?.toString().trim() ?? '')
            .where((name) => name.isNotEmpty)
            .toList();
      }
      if (decoded is Map) {
        final name = decoded['Name']?.toString().trim();
        return name == null || name.isEmpty ? const <String>[] : <String>[name];
      }
    }

    return const <String>[];
  }

  Future<String?> _getDefaultPrinter() async {
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('lpstat', ['-d']);
      if (result.exitCode != 0) {
        return null;
      }
      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return null;
      }
      final match = RegExp(r':\s*(.+)$').firstMatch(output);
      return match?.group(1)?.trim();
    }

    if (Platform.isWindows) {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'Get-CimInstance Win32_Printer | Where-Object {$_.Default -eq $true} | Select-Object -First 1 Name | ConvertTo-Json -Compress',
      ]);
      if (result.exitCode != 0) {
        return null;
      }
      final raw = result.stdout.toString().trim();
      if (raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded['Name']?.toString().trim();
      }
    }

    return null;
  }
}
