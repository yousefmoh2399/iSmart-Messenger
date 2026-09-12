import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/shared/services/print_job_processor.dart';
import 'package:desktop_app/shared/services/print_job_tracker.dart';
import 'package:desktop_app/shared/services/desktop_print_service.dart';

class MockPrintExecutor implements PrintExecutor {
  int executeCalls = 0;
  bool shouldSucceed = true;
  String? lastPrinterName;

  @override
  Future<DesktopPrintResult> executePrintJob(
    Map<String, dynamic> payload, {
    String? preferredPrinterName,
  }) async {
    executeCalls++;
    lastPrinterName = preferredPrinterName ?? 'MockPrinter';
    // Simulate delay for concurrency tests
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return DesktopPrintResult(
      success: shouldSucceed,
      message: shouldSucceed ? 'Success' : 'Failed',
      printerName: lastPrinterName,
    );
  }
}

class MockPrintStatusEmitter implements PrintStatusEmitter {
  final List<Map<String, dynamic>> emittedEvents = [];

  @override
  void emitEvent(String eventName, Map<String, dynamic> payload) {
    emittedEvents.add({
      'eventName': eventName,
      'payload': Map<String, dynamic>.from(payload),
    });
  }
}

class MockPrintLogger implements PrintLogger {
  final List<String> logs = [];

  @override
  void info(String message) => logs.add('INFO: $message');
  @override
  void warn(String message) => logs.add('WARN: $message');
  @override
  void error(String message) => logs.add('ERROR: $message');
}

class MockPrintJobStore implements PrintJobStore {
  List<PrintJobRecord> records = [];
  bool saveShouldFail = false;

  @override
  Future<List<PrintJobRecord>> loadRecords() async {
    return List<PrintJobRecord>.from(records);
  }

  @override
  Future<bool> saveRecords(List<PrintJobRecord> newRecords) async {
    if (saveShouldFail) {
      return false;
    }
    records = List<PrintJobRecord>.from(newRecords);
    return true;
  }
}

void main() {
  group('PrintJobProcessor Integration Tests', () {
    test('same jobId x4 concurrently prints exactly once and emits duplicate update', () async {
      final store = MockPrintJobStore();
      final tracker = PrintJobTracker(store);
      final executor = MockPrintExecutor();
      final emitter = MockPrintStatusEmitter();
      final logger = MockPrintLogger();
      final processor = PrintJobProcessor(
        tracker: tracker,
        executor: executor,
        statusEmitter: emitter,
        logger: logger,
      );

      final payload = {'jobId': 'job-123', 'fileName': 'test.pdf'};

      // Send same payload concurrently 4 times
      final results = await Future.wait([
        processor.process(payload),
        processor.process(payload),
        processor.process(payload),
        processor.process(payload),
      ]);

      // Exactly one should succeed as submitted, others as duplicateIgnored
      final submittedCount = results.where((r) => r.status == PrintJobProcessStatus.submitted).length;
      final duplicateCount = results.where((r) => r.status == PrintJobProcessStatus.duplicateIgnored).length;

      expect(submittedCount, equals(1));
      expect(duplicateCount, equals(3));

      expect(executor.executeCalls, equals(1));
      expect(store.records.length, equals(1));

      // Verify status updates
      final updates = emitter.emittedEvents.where((e) => e['eventName'] == 'print_job_status_update').toList();
      expect(updates.length, equals(4)); // 1 processing + 3 duplicate_ignored
      
      final duplicateUpdates = updates.where((u) => u['payload']['status'] == 'duplicate_ignored').toList();
      expect(duplicateUpdates.length, equals(3));

      final resultsEmitted = emitter.emittedEvents.where((e) => e['eventName'] == 'print_job_result').toList();
      expect(resultsEmitted.length, equals(1));
      expect(resultsEmitted.first['payload']['status'], equals('completed'));
      expect(resultsEmitted.first['payload']['success'], isTrue);
    });

    test('persistence survives restart and ignores subsequent prints', () async {
      final store = MockPrintJobStore();
      final tracker1 = PrintJobTracker(store);
      final executor1 = MockPrintExecutor();
      final emitter1 = MockPrintStatusEmitter();
      final logger1 = MockPrintLogger();
      
      final processor1 = PrintJobProcessor(
        tracker: tracker1,
        executor: executor1,
        statusEmitter: emitter1,
        logger: logger1,
      );

      final payload = {'jobId': 'job-123', 'fileName': 'test.pdf'};
      final res1 = await processor1.process(payload);
      expect(res1.status, equals(PrintJobProcessStatus.submitted));
      expect(executor1.executeCalls, equals(1));

      // Simulate Restart: Create a new Tracker/Processor using the same store
      final tracker2 = PrintJobTracker(store);
      final executor2 = MockPrintExecutor();
      final emitter2 = MockPrintStatusEmitter();
      final logger2 = MockPrintLogger();

      final processor2 = PrintJobProcessor(
        tracker: tracker2,
        executor: executor2,
        statusEmitter: emitter2,
        logger: logger2,
      );

      // Process the same jobId again
      final res2 = await processor2.process(payload);
      expect(res2.status, equals(PrintJobProcessStatus.duplicateIgnored));
      expect(executor2.executeCalls, equals(0));

      // Status response emitted: 1 submitted status update
      final updates = emitter2.emittedEvents.where((e) => e['eventName'] == 'print_job_status_update').toList();
      expect(updates.length, equals(1));
      expect(updates.first['payload']['status'], equals('submitted'));
    });

    test('persistence failure does not reprint and log contains persistence_failed', () async {
      final store = MockPrintJobStore();
      store.saveShouldFail = true; // DB/SharedPreferences write fails
      
      final tracker = PrintJobTracker(store);
      final executor = MockPrintExecutor();
      final emitter = MockPrintStatusEmitter();
      final logger = MockPrintLogger();

      final processor = PrintJobProcessor(
        tracker: tracker,
        executor: executor,
        statusEmitter: emitter,
        logger: logger,
      );

      final payload = {'jobId': 'job-fail-db', 'fileName': 'test.pdf'};
      final result1 = await processor.process(payload);

      // Even if database save failed, process returns submitted (since executor succeeded)
      expect(result1.status, equals(PrintJobProcessStatus.submitted));
      expect(executor.executeCalls, equals(1));

      // Logs must contain persistence_failed
      expect(logger.logs.any((l) => l.contains('persistence_failed')), isTrue);

      // Same session duplicate arrives
      final result2 = await processor.process(payload);
      expect(result2.status, equals(PrintJobProcessStatus.duplicateIgnored));
      
      // Executor must NOT be called again
      expect(executor.executeCalls, equals(1));
    });
  });
}
