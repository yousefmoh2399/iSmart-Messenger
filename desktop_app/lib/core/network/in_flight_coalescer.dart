import 'dart:async';

/// Coalesces concurrent async fetches sharing [key] inside [inFlight].
///
/// Uses an explicit [Completer] instead of `.whenComplete(() => map.remove(key))`
/// because returning the removed [Future] from `whenComplete` causes Dart's
/// `Future.whenComplete` to await itself indefinitely.
Future<T> runCoalescedInFlight<T>(
  Map<String, Future<T>> inFlight,
  String key,
  Future<T> Function() loader,
) {
  final existing = inFlight[key];
  if (existing != null) {
    return existing;
  }

  final completer = Completer<T>();
  final tracked = completer.future;
  inFlight[key] = tracked;

  Future<T>.sync(loader).then(
    (value) {
      if (identical(inFlight[key], tracked)) {
        inFlight.remove(key);
      }
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (identical(inFlight[key], tracked)) {
        inFlight.remove(key);
      }
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );

  return tracked;
}
