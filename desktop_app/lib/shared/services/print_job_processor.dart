import 'dart:async';
import 'package:flutter/foundation.dart';
import 'desktop_print_service.dart';
import 'print_job_tracker.dart';

abstract class PrintExecutor {
  Future<DesktopPrintResult> executePrintJob(
    Map<String, dynamic> payload, {
    String? preferredPrinterName,
  });
}

abstract class PrintStatusEmitter {
  void emitEvent(String eventName, Map<String, dynamic> payload);
}

abstract class PrintLogger {
  void info(String message);
  void warn(String message);
  void error(String message);
}

enum PrintJobProcessStatus { submitted, duplicateIgnored, failed }

class PrintJobProcessResult {
  PrintJobProcessResult({required this.status, this.message, this.printerName});

  final PrintJobProcessStatus status;
  final String? message;
  final String? printerName;
}

class PrintJobProcessor {
  PrintJobProcessor({
    required PrintJobTracker tracker,
    required PrintExecutor executor,
    required PrintStatusEmitter statusEmitter,
    required PrintLogger logger,
  }) : _tracker = tracker,
       _executor = executor,
       _statusEmitter = statusEmitter,
       _logger = logger;

  final PrintJobTracker _tracker;
  final PrintExecutor _executor;
  final PrintStatusEmitter _statusEmitter;
  final PrintLogger _logger;

  Future<PrintJobProcessResult> process(
    Map<String, dynamic> payload, {
    String? preferredPrinterName,
  }) async {
    final jobId = payload['jobId']?.toString();
    if (jobId == null || jobId.isEmpty) {
      _logger.warn('Received print job with empty jobId.');
      return PrintJobProcessResult(
        status: PrintJobProcessStatus.failed,
        message: 'Empty jobId',
      );
    }

    final claimResult = await _tracker.claim(jobId);

    if (claimResult == PrintJobClaimResult.alreadyProcessing) {
      _logger.info('Duplicate print job ignored (processing): $jobId');
      _statusEmitter.emitEvent('print_job_status_update', <String, dynamic>{
        'jobId': jobId,
        'status': 'duplicate_ignored',
      });
      return PrintJobProcessResult(
        status: PrintJobProcessStatus.duplicateIgnored,
        message: 'Already processing',
      );
    }

    if (claimResult == PrintJobClaimResult.alreadySubmitted) {
      _logger.info('Duplicate print job ignored (submitted): $jobId');
      _statusEmitter.emitEvent('print_job_status_update', <String, dynamic>{
        'jobId': jobId,
        'status': 'submitted',
      });
      return PrintJobProcessResult(
        status: PrintJobProcessStatus.duplicateIgnored,
        message: 'Already submitted',
      );
    }

    // State: Processing
    _statusEmitter.emitEvent('print_job_status_update', <String, dynamic>{
      'jobId': jobId,
      'status': 'processing',
    });

    final result = await _executor.executePrintJob(
      payload,
      preferredPrinterName: preferredPrinterName,
    );

    if (result.success) {
      // 1. Persist submitted locally
      final saveSuccess = await _tracker.markSubmitted(
        jobId,
        fileName: payload['fileName']?.toString(),
        printerName: result.printerName,
      );

      if (!saveSuccess) {
        _logger.error(
          'event=persistence_failed jobId=$jobId message="Failed to save print job locally."',
        );
      }

      // 2. Emit result to backend
      _statusEmitter.emitEvent('print_job_result', <String, dynamic>{
        'jobId': jobId,
        'success': true,
        'status': 'completed', // backward compatibility fallback
        'executionState': 'submitted',
        'printerName': result.printerName,
      });

      return PrintJobProcessResult(
        status: PrintJobProcessStatus.submitted,
        message: result.message,
        printerName: result.printerName,
      );
    } else {
      // Release processing state so retry is possible
      _tracker.releaseProcessing(jobId);

      _statusEmitter.emitEvent('print_job_result', <String, dynamic>{
        'jobId': jobId,
        'success': false,
        'status': 'failed',
        'executionState': 'failed',
        'message': result.message,
        'printerName': result.printerName,
      });

      return PrintJobProcessResult(
        status: PrintJobProcessStatus.failed,
        message: result.message,
        printerName: result.printerName,
      );
    }
  }
}

class ConsolePrintLogger implements PrintLogger {
  @override
  void info(String message) => debugPrint('INFO: $message');
  @override
  void warn(String message) => debugPrint('WARN: $message');
  @override
  void error(String message) => debugPrint('ERROR: $message');
}
