import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_app/shared/services/print_job_tracker.dart';

class MockPrintJobStore implements PrintJobStore {
  List<PrintJobRecord> records = <PrintJobRecord>[];
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
  group('PrintJobTracker Tests', () {
    late MockPrintJobStore mockStore;
    late PrintJobTracker tracker;

    setUp(() {
      mockStore = MockPrintJobStore();
      tracker = PrintJobTracker(mockStore);
    });

    test('Claiming a new print job returns claimed status', () async {
      final result = await tracker.claim('job-1');
      expect(result, PrintJobClaimResult.claimed);
      expect(tracker.isJobProcessingInMemory('job-1'), isTrue);
    });

    test('Claiming a processing print job returns alreadyProcessing status', () async {
      await tracker.claim('job-1');
      final result = await tracker.claim('job-1');
      expect(result, PrintJobClaimResult.alreadyProcessing);
    });

    test('Claiming a submitted print job returns alreadySubmitted status', () async {
      await tracker.claim('job-1');
      await tracker.markSubmitted('job-1', fileName: 'test.pdf', printerName: 'Printer1');
      
      final result = await tracker.claim('job-1');
      expect(result, PrintJobClaimResult.alreadySubmitted);
    });

    test('Releasing a processing job allows claiming it again', () async {
      await tracker.claim('job-1');
      expect(tracker.isJobProcessingInMemory('job-1'), isTrue);
      
      tracker.releaseProcessing('job-1');
      expect(tracker.isJobProcessingInMemory('job-1'), isFalse);
      
      final claimRes = await tracker.claim('job-1');
      expect(claimRes, PrintJobClaimResult.claimed);
    });

    test('markSubmitted cleans up old records exceeding 500 limit', () async {
      // Seed store with 500 existing records with deterministic old timestamps
      final oldRecords = List<PrintJobRecord>.generate(500, (index) {
        return PrintJobRecord(
          jobId: 'old-job-$index',
          status: 'submitted',
          submittedAt: DateTime.now().subtract(Duration(minutes: 1000 - index)).toIso8601String(),
          updatedAt: DateTime.now().subtract(Duration(minutes: 1000 - index)).toIso8601String(),
        );
      });
      mockStore.records = oldRecords;

      // Add a new job
      await tracker.claim('new-job-1');
      await tracker.markSubmitted('new-job-1');

      final finalRecords = await mockStore.loadRecords();
      // Should not exceed 500
      expect(finalRecords.length, equals(500));
      expect(finalRecords.any((r) => r.jobId == 'new-job-1'), isTrue);
      // The oldest job (old-job-0) should be removed
      expect(finalRecords.any((r) => r.jobId == 'old-job-0'), isFalse);
    });

    test('markSubmitted cleans up old records older than 7 days', () async {
      final oldJob = PrintJobRecord(
        jobId: 'ancient-job',
        status: 'submitted',
        submittedAt: DateTime.now().subtract(const Duration(days: 8)).toIso8601String(),
        updatedAt: DateTime.now().subtract(const Duration(days: 8)).toIso8601String(),
      );
      mockStore.records = <PrintJobRecord>[oldJob];

      await tracker.claim('new-job-2');
      await tracker.markSubmitted('new-job-2');

      final finalRecords = await mockStore.loadRecords();
      expect(finalRecords.length, equals(1));
      expect(finalRecords.any((r) => r.jobId == 'ancient-job'), isFalse);
      expect(finalRecords.any((r) => r.jobId == 'new-job-2'), isTrue);
    });

    test('Fail-safe handles local persistence failure gracefully without reprint or failed state', () async {
      mockStore.saveShouldFail = true;

      await tracker.claim('job-fail-persist');
      final result = await tracker.markSubmitted('job-fail-persist');
      expect(result, isFalse); // Save failed

      // In-memory status should still be correct (failsafe keeps it submitted)
      expect(tracker.isJobSubmittedInMemory('job-fail-persist'), isTrue);
      expect(tracker.isJobProcessingInMemory('job-fail-persist'), isFalse);

      // Re-claiming should still return alreadySubmitted
      final claimRes = await tracker.claim('job-fail-persist');
      expect(claimRes, PrintJobClaimResult.alreadySubmitted);
    });

    test('Claim concurrency handles overlapping parallel claims deterministically', () async {
      final claims = await Future.wait<PrintJobClaimResult>([
        tracker.claim('concurrent-job'),
        tracker.claim('concurrent-job'),
        tracker.claim('concurrent-job'),
      ]);

      // Exactly one claim must succeed, others must be rejected
      final claimedCount = claims.where((c) => c == PrintJobClaimResult.claimed).length;
      final processingCount = claims.where((c) => c == PrintJobClaimResult.alreadyProcessing).length;

      expect(claimedCount, equals(1));
      expect(processingCount, equals(2));
    });
  });
}
