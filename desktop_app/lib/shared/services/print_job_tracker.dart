import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum PrintJobClaimResult { claimed, alreadyProcessing, alreadySubmitted }

class PrintJobRecord {
  PrintJobRecord({
    required this.jobId,
    required this.status,
    this.fileName,
    this.printerName,
    this.submittedAt,
    required this.updatedAt,
  });

  factory PrintJobRecord.fromJson(Map<String, dynamic> json) {
    return PrintJobRecord(
      jobId: json['jobId'] as String,
      status: json['status'] as String,
      fileName: json['fileName'] as String?,
      printerName: json['printerName'] as String?,
      submittedAt: json['submittedAt'] as String?,
      updatedAt: json['updatedAt'] as String,
    );
  }

  final String jobId;
  final String status;
  final String? fileName;
  final String? printerName;
  final String? submittedAt;
  final String updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'jobId': jobId,
    'status': status,
    'fileName': fileName,
    'printerName': printerName,
    'submittedAt': submittedAt,
    'updatedAt': updatedAt,
  };
}

abstract class PrintJobStore {
  Future<List<PrintJobRecord>> loadRecords();
  Future<bool> saveRecords(List<PrintJobRecord> records);
}

class SharedPreferencesPrintJobStore implements PrintJobStore {
  SharedPreferencesPrintJobStore();
  static const String _key = 'processed_print_jobs';

  @override
  Future<List<PrintJobRecord>> loadRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_key);
      if (jsonStr == null || jsonStr.isEmpty) {
        return <PrintJobRecord>[];
      }
      final rawList = jsonDecode(jsonStr);
      if (rawList is! List) {
        return <PrintJobRecord>[];
      }
      return rawList
          .map((dynamic e) {
            try {
              if (e is Map<String, dynamic>) {
                return PrintJobRecord.fromJson(e);
              }
            } catch (_) {}
            return null;
          })
          .whereType<PrintJobRecord>()
          .toList();
    } catch (_) {
      // Return empty list on parse error as fail-safe
      return <PrintJobRecord>[];
    }
  }

  @override
  Future<bool> saveRecords(List<PrintJobRecord> records) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(records.map((r) => r.toJson()).toList());
      return await prefs.setString(_key, jsonStr);
    } catch (_) {
      return false;
    }
  }
}

class AsyncMutex {
  Future<void> _last = Future<void>.value();
  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _last.whenComplete(() {
      action().then(completer.complete, onError: completer.completeError);
    });
    _last = completer.future.then<void>((_) {}, onError: (_) {});
    return completer.future;
  }
}

class PrintJobTracker {
  PrintJobTracker(this.store);

  final PrintJobStore store;
  final Set<String> _processingJobIds = <String>{};
  final Set<String> _submittedJobIds = <String>{};
  final AsyncMutex _mutex = AsyncMutex();
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _mutex.run(() async {
      if (_loaded) return;
      final records = await store.loadRecords();
      for (final r in records) {
        if (r.status == 'submitted') {
          _submittedJobIds.add(r.jobId);
        }
      }
      _loaded = true;
    });
  }

  Future<PrintJobClaimResult> claim(String jobId) async {
    await ensureLoaded();
    return _mutex.run(() async {
      if (_submittedJobIds.contains(jobId)) {
        return PrintJobClaimResult.alreadySubmitted;
      }
      if (_processingJobIds.contains(jobId)) {
        return PrintJobClaimResult.alreadyProcessing;
      }
      _processingJobIds.add(jobId);
      return PrintJobClaimResult.claimed;
    });
  }

  void releaseProcessing(String jobId) {
    _processingJobIds.remove(jobId);
  }

  Future<bool> markSubmitted(
    String jobId, {
    String? fileName,
    String? printerName,
  }) async {
    _processingJobIds.remove(jobId);
    _submittedJobIds.add(jobId);

    bool saveSuccess = false;
    await _mutex.run(() async {
      final records = await store.loadRecords();

      // Update or insert new record
      final existingIndex = records.indexWhere((r) => r.jobId == jobId);
      final newRecord = PrintJobRecord(
        jobId: jobId,
        status: 'submitted',
        fileName: fileName,
        printerName: printerName,
        submittedAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );

      if (existingIndex != -1) {
        records[existingIndex] = newRecord;
      } else {
        records.add(newRecord);
      }

      // Cleanup strategy: keep last 500 records or last 7 days
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      records.removeWhere((r) {
        try {
          final submittedDate = DateTime.parse(r.submittedAt ?? r.updatedAt);
          return submittedDate.isBefore(cutoff);
        } catch (_) {
          return false;
        }
      });

      if (records.length > 500) {
        records.sort(
          (a, b) => (a.submittedAt ?? a.updatedAt).compareTo(
            b.submittedAt ?? b.updatedAt,
          ),
        );
        records.removeRange(0, records.length - 500);
      }

      saveSuccess = await store.saveRecords(records);
    });

    return saveSuccess;
  }

  // Diagnostic API to check if job is submitted or processing in memory
  bool isJobProcessingInMemory(String jobId) =>
      _processingJobIds.contains(jobId);
  bool isJobSubmittedInMemory(String jobId) => _submittedJobIds.contains(jobId);
}
